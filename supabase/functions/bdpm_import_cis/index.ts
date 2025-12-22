// Supabase Edge Function: bdpm_import_cis
// - Importe CIS_bdpm.txt -> table public.drugs
// - Supporte un mode streaming par bytes (HTTP Range) pour limiter le CPUTime par appel
// - Finalisation séparée pour mettre à jour drug_metadata.count_drugs

import { serve } from 'https://deno.land/std@0.224.0/http/server.ts';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.47.10';

type Json = Record<string, unknown>;

const SUPABASE_URL = Deno.env.get('SUPABASE_URL')!;
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, {
  auth: { persistSession: false },
});

const BDPM_CIS_URL = 'https://base-donnees-publique.medicaments.gouv.fr/download/file/CIS_bdpm.txt';
const METADATA_ID = '00000000-0000-0000-0000-000000000001';

const corsHeaders: Record<string, string> = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

function decodeBuffer(buf: ArrayBuffer, contentType: string | null): string {
  const ct = contentType?.toLowerCase() ?? '';
  const charsetMatch = ct.match(/charset\s*=\s*([^;\s]+)/i);
  const charset = charsetMatch ? charsetMatch[1].trim() : '';
  try {
    if (charset.includes('iso-8859-1') || charset.includes('latin1') || charset.includes('windows-1252')) {
      return new TextDecoder('windows-1252', { fatal: false }).decode(buf);
    }
    let txt = new TextDecoder('utf-8', { fatal: false }).decode(buf);
    if (txt.includes('\uFFFD')) {
      const alt = new TextDecoder('windows-1252', { fatal: false }).decode(buf);
      const repUtf8 = (txt.match(/\uFFFD/g) || []).length;
      const rep1252 = (alt.match(/\uFFFD/g) || []).length;
      if (rep1252 < repUtf8) return alt;
    }
    return txt;
  } catch (_) {
    try {
      return new TextDecoder('windows-1252', { fatal: false }).decode(buf);
    } catch (_) {
      return new TextDecoder().decode(buf);
    }
  }
}

async function fetchRangeText(url: string, start: number, maxBytes: number): Promise<{ text: string; bytesRead: number; isPartial: boolean; }> {
  const end = start + Math.max(0, maxBytes) - 1;
  const resp = await fetch(url, {
    redirect: 'follow',
    headers: { 'Range': `bytes=${start}-${end}` },
  });
  if (!resp.ok && resp.status !== 206) {
    throw new Error(`Téléchargement (Range) échoué (${url}): ${resp.status} ${resp.statusText}`);
  }
  const buf = await resp.arrayBuffer();
  const text = decodeBuffer(buf, resp.headers.get('content-type'))
    .replaceAll('\r\n', '\n')
    .replaceAll('\r', '\n');
  let bytesRead = 0;
  const cr = resp.headers.get('Content-Range');
  if (cr) {
    const m = cr.match(/bytes\s+(\d+)-(\d+)\/(\d+)/i);
    if (m) {
      const s = Number(m[1]);
      const e = Number(m[2]);
      if (Number.isFinite(s) && Number.isFinite(e)) bytesRead = (e - s + 1);
    }
  }
  if (!bytesRead) bytesRead = new TextEncoder().encode(text).length;
  const isPartial = resp.status === 206;
  return { text, bytesRead, isPartial };
}

function splitList(input: string): string[] | null {
  const v = input?.trim();
  if (!v) return null;
  const list = v
    .split(';')
    .map((x) => x.trim())
    .filter((x) => x && x.toLowerCase() !== 'inconnu');
  return list.length ? list : null;
}

function parseFrDate(input: string): string | null {
  const v = input?.trim();
  if (!v) return null;
  const parts = v.split('/');
  if (parts.length !== 3) return null;
  const dd = Number(parts[0]);
  const mm = Number(parts[1]);
  const yyyy = Number(parts[2]);
  if (!dd || !mm || !yyyy) return null;
  const dt = new Date(Date.UTC(yyyy, mm - 1, dd));
  return dt.toISOString();
}

function toBool(input: string): boolean | null {
  const v = (input || '').trim().toLowerCase();
  if (v === 'oui') return true;
  if (v === 'non') return false;
  return null;
}

function parseCisLines(lines: string[]): Json[] {
  const rows: Json[] = [];
  for (const line of lines) {
    const cols = line.split('\t');
    if (!cols.length || !cols[0].trim()) continue;
    if (cols[0].trim().toLowerCase() === 'cis' || cols[0].includes('Code CIS')) continue;
    const cis = Number(cols[0].trim());
    if (!Number.isFinite(cis)) continue;
    const denomination = cols[1]?.trim() ?? '';
    const forme = cols[2]?.trim() ?? '';
    const voies = cols[3]?.trim() ?? '';
    const statutAmm = cols[4]?.trim() ?? '';
    // type_procedure_amm ignoré pour alléger (cols[5])
    const etatComm = cols[6]?.trim() ?? '';
    // date_amm ignorée (cols[7])
    const statutBdm = cols[8]?.trim() ?? '';
    // numero_autorisation_europeenne ignoré (cols[9])
    const titulaires = cols[10]?.trim() ?? '';
    const surv = cols[11]?.trim() ?? '';

    rows.push({
      cis,
      denomination,
      forme: forme || null,
      voies: splitList(voies),
      statut_amm: statutAmm || null,
      etat_commercialisation: etatComm || null,
      statut_bdm: statutBdm || null,
      titulaires: splitList(titulaires),
      surveillance_renforcee: toBool(surv),
    });
  }
  return rows;
}

async function loadCisChunk(byteOffset: number, maxBytes: number, carry: string): Promise<{
  rows: Json[];
  bytesRead: number;
  nextByteOffset: number;
  carryOut: string;
  isPartial: boolean;
}> {
  const { text, bytesRead, isPartial } = await fetchRangeText(BDPM_CIS_URL, byteOffset, maxBytes);
  const combined = (carry || '') + text.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
  const parts = combined.split('\n');
  const last = parts[parts.length - 1];
  const fullLines = combined.endsWith('\n') ? parts : parts.slice(0, -1);
  const carryOut = combined.endsWith('\n') ? '' : last;
  const rows = parseCisLines(fullLines);
  return {
    rows,
    bytesRead,
    nextByteOffset: byteOffset + bytesRead,
    carryOut,
    isPartial,
  };
}

async function upsertInBatches(
  table: string,
  rows: Json[],
  onConflict: string,
  batchSize = 2500, // CIS: plus gros batchs
) {
  for (let i = 0; i < rows.length; i += batchSize) {
    const end = Math.min(i + batchSize, rows.length);
    const chunk = rows.slice(i, end);
    let resp: any;
    try {
      resp = await supabase
        .from(table)
        .upsert(chunk, { onConflict, returning: 'minimal' as any });
    } catch (e) {
      throw new Error(`Upsert ${table} a échoué (batch ${i}-${end}): ${(e as Error).message}`);
    }
    if (!resp || typeof resp !== 'object') {
      throw new Error(`Réponse invalide de Supabase lors de l'upsert ${table} (batch ${i}-${end}).`);
    }
    if (resp.error) {
      throw new Error(`Upsert ${table} a renvoyé une erreur: ${resp.error.message || resp.error}`);
    }
  }
}

async function runWithBody(body: any): Promise<Response> {
  const startedAt = new Date();
  try {
    const finalize = !!(body && body.finalize === true);
    if (finalize) {
      const cntResp: any = await supabase
        .from('drugs')
        .select('cis', { count: 'exact', head: true } as any);
      if (!cntResp || typeof cntResp !== 'object') {
        throw new Error('Réponse invalide lors du comptage des CIS');
      }
      if (cntResp.error) throw cntResp.error;
      const countDrugs = typeof cntResp.count === 'number' ? cntResp.count : null;
      const metaResp = await supabase.from('drug_metadata').upsert(
        {
          id: METADATA_ID,
          last_imported_at: new Date().toISOString(),
          source: 'BDPM',
          count_drugs: countDrugs,
        },
        { onConflict: 'id' } as any,
      );
      if (!metaResp || typeof metaResp !== 'object') {
        throw new Error('Réponse invalide lors de la mise à jour drug_metadata');
      }
      if ((metaResp as any).error) throw (metaResp as any).error;
      return new Response(JSON.stringify({ ok: true, count_drugs: countDrugs, message: 'Finalisation CIS OK' }), {
        headers: { 'content-type': 'application/json; charset=utf-8', ...corsHeaders },
        status: 200,
      });
    }

    const byteOffset = (body && typeof body.byte_offset === 'number' && body.byte_offset >= 0) ? body.byte_offset as number : 0;
    const maxBytes = (body && typeof body.max_bytes === 'number' && body.max_bytes > 0) ? Math.min(512_000, body.max_bytes as number) : 256_000;
    const carryIn = (body && typeof body.carry === 'string') ? (body.carry as string) : '';

    const chunk = await loadCisChunk(byteOffset, maxBytes, carryIn);
    const drugs = chunk.rows;

    await upsertInBatches('drugs', drugs, 'cis', 2000);

    const payload = {
      ok: true,
      message: drugs.length > 0
        ? `CIS chunk traité: ${drugs.length} (byte_offset=${byteOffset})`
        : 'Aucun enregistrement CIS à traiter pour ce chunk',
      processed: drugs.length,
      next_byte_offset: chunk.nextByteOffset,
      carry: chunk.carryOut,
      is_partial: chunk.isPartial,
      finished_at: new Date().toISOString(),
      duration_s: Math.round((Date.now() - startedAt.getTime()) / 1000),
    } as Record<string, unknown>;
    return new Response(JSON.stringify(payload), {
      headers: { 'content-type': 'application/json; charset=utf-8', ...corsHeaders },
      status: 200,
    });
  } catch (e) {
    const err = e as Error;
    const payload = { ok: false, error: err.message };
    return new Response(JSON.stringify(payload), {
      headers: { 'content-type': 'application/json; charset=utf-8', ...corsHeaders },
      status: 500,
    });
  }
}

export default async function handler(req: Request): Promise<Response> {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: { ...corsHeaders } });
  }
  if (req.method !== 'POST') {
    return new Response(JSON.stringify({ ok: false, error: 'Méthode non autorisée' }), {
      headers: { 'content-type': 'application/json; charset=utf-8', ...corsHeaders },
      status: 405,
    });
  }
  let body: any = {};
  try {
    if (req.headers.get('content-type')?.includes('application/json')) {
      body = await req.json().catch(() => ({}));
    }
  } catch (_) {
    body = {};
  }
  return runWithBody(body);
}

// Démarre le serveur pour que la fonction réponde (y compris au preflight OPTIONS)
serve(handler);
