// Supabase Edge Function: bdpm_import_cis_cip
// - Importe le fichier officiel BDPM: CIS_CIP_bdpm.txt -> table public.presentations (CIP13)
// - Pensée pour une exécution en petits chunks, en utilisant HTTP Range pour limiter la lecture
// - Evite de parser tout le fichier à chaque appel (réduction du CPUTime)
// - Finalisation séparée pour mettre à jour drug_metadata.count_presentations

import { serve } from 'https://deno.land/std@0.224.0/http/server.ts';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.47.10';

type Json = Record<string, unknown>;

const SUPABASE_URL = Deno.env.get('SUPABASE_URL')!;
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, {
  auth: { persistSession: false },
});

const BDPM_CIS_CIP_URL = 'https://base-donnees-publique.medicaments.gouv.fr/download/file/CIS_CIP_bdpm.txt';
const METADATA_ID = '00000000-0000-0000-0000-000000000001';

const corsHeaders: Record<string, string> = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

// Décode un ArrayBuffer en texte en respectant l'encodage quand il est fourni.
function decodeBuffer(buf: ArrayBuffer, contentType: string | null): string {
  const ct = contentType?.toLowerCase() ?? '';
  // Tenter d'honorer le charset si présent
  const charsetMatch = ct.match(/charset\s*=\s*([^;\s]+)/i);
  const charset = charsetMatch ? charsetMatch[1].trim() : '';
  try {
    if (charset.includes('iso-8859-1') || charset.includes('latin1') || charset.includes('windows-1252')) {
      // Deno supporte windows-1252
      return new TextDecoder('windows-1252', { fatal: false }).decode(buf);
    }
    // Essai UTF-8 par défaut
    let txt = new TextDecoder('utf-8', { fatal: false }).decode(buf);
    if (txt.includes('\uFFFD')) {
      // Si beaucoup de caractères de remplacement, tenter windows-1252
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

// Télécharge une fenêtre de bytes avec Range. Retourne le texte du chunk et les bytes effectivement lus
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
  // bytesRead: essayer d'utiliser Content-Range, sinon fallback à length estimée en UTF-16 -> ce sera approximatif;
  // mais comme nous enchaînons en chaîne, on se base surtout sur Content-Range.
  let bytesRead = 0;
  const cr = resp.headers.get('Content-Range');
  if (cr) {
    // format ex: bytes 0-1023/999999
    const m = cr.match(/bytes\s+(\d+)-(\d+)\/(\d+)/i);
    if (m) {
      const s = Number(m[1]);
      const e = Number(m[2]);
      if (Number.isFinite(s) && Number.isFinite(e)) bytesRead = (e - s + 1);
    }
  }
  if (!bytesRead) {
    // fallback approximatif: nombre de code units -> ce n'est pas exact en bytes, mais acceptable si Range non supporté
    bytesRead = new TextEncoder().encode(text).length;
  }
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

// parseCis supprimé ici (non utilisé); la fonction CIS dédiée importe les spécialités

// Extrait un nombre depuis une chaîne prix ("12,34 €" -> 12.34)
function parsePrice(input: string): number | null {
  const v = (input || '').replace('€', '').replace(/\s+/g, '').replace(',', '.');
  const n = Number(v);
  return Number.isFinite(n) ? n : null;
}

function parseCisCipLines(lines: string[]): Json[] {
  const rows: Json[] = [];
  for (const line of lines) {
    const cols = line.split('\t');
    if (!cols.length || !cols[0].trim()) continue;
    if (cols[0].trim().toLowerCase() === 'cis' || cols[0].includes('Code CIS')) continue;
    const cis = Number(cols[0].trim());
    if (!Number.isFinite(cis)) continue;
    const cip7 = cols[1]?.trim() ?? '';
    const libelle = cols[2]?.trim() ?? '';
    const statutAdmin = cols[3]?.trim() ?? '';
    const etatComm = cols[4]?.trim() ?? '';
    // date_declaration ignorée pour alléger (cols[5])
    const cip13 = cols[6]?.trim() ?? '';
    // agrement_collectivites ignoré (cols[7])
    const taux = cols[8]?.trim() ?? '';

    // Prix: certains dumps contiennent 3 colonnes de prix (HT, TTC, marge)
    // On ne conserve QUE le second (TTC avec marge). Si une seule colonne, on la prend.
    let prixTtc: number | null = null;
    const tail = cols.slice(9, 14); // scanner quelques colonnes suivantes sans supposer la largeur exacte
    const foundPrices: number[] = [];
    for (const c of tail) {
      const n = parsePrice(c?.trim() ?? '');
      if (n !== null) foundPrices.push(n);
    }
    if (foundPrices.length >= 2) prixTtc = foundPrices[1];
    else if (foundPrices.length === 1) prixTtc = foundPrices[0];

    // indications_remboursement ignorées pour alléger
    if (!cip13) continue;

    rows.push({
      cis,
      cip7: cip7 || null,
      libelle: libelle || null,
      statut_admin: statutAdmin || null,
      etat_commercialisation: etatComm || null,
      cip13,
      taux_remboursement: splitList(taux),
      prix_euro: prixTtc,
    });
  }
  return rows;
}

// Lit un morceau du fichier CIP via Range, gère la dernière ligne incomplète via "carry"
async function loadCipChunk(byteOffset: number, maxBytes: number, carry: string): Promise<{
  rows: Json[];
  bytesRead: number;
  nextByteOffset: number;
  carryOut: string;
  isPartial: boolean;
}> {
  const { text, bytesRead, isPartial } = await fetchRangeText(BDPM_CIS_CIP_URL, byteOffset, maxBytes);
  const combined = (carry || '') + text;
  const parts = combined.split('\n');
  // Si le chunk se termine sans saut de ligne, la dernière entrée est incomplète -> carryOut
  const last = parts[parts.length - 1];
  const fullLines = combined.endsWith('\n') ? parts : parts.slice(0, -1);
  const carryOut = combined.endsWith('\n') ? '' : last;
  const rows = parseCisCipLines(fullLines);
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
  // Important: conserver un batch très petit pour limiter le coût JSON.stringify côté edge (CPUTime)
  batchSize = 200,
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
    // Modes: finalize | stream chunk
    const finalize = !!(body && body.finalize === true);

    // Finalisation rapide: compter les présentations en base et mettre à jour les métadonnées
    if (finalize) {
      const cntResp: any = await supabase
        .from('presentations')
        .select('cip13', { count: 'exact', head: true } as any);
      if (!cntResp || typeof cntResp !== 'object') {
        throw new Error('Réponse invalide lors du comptage des présentations');
      }
      if (cntResp.error) throw cntResp.error;
      const countPresentations = typeof cntResp.count === 'number' ? cntResp.count : null;
      const metaResp = await supabase.from('drug_metadata').upsert(
        {
          id: METADATA_ID,
          last_imported_at: new Date().toISOString(),
          source: 'BDPM',
          count_presentations: countPresentations,
        },
        { onConflict: 'id' } as any,
      );
      if (!metaResp || typeof metaResp !== 'object') {
        throw new Error('Réponse invalide lors de la mise à jour drug_metadata');
      }
      if ((metaResp as any).error) throw (metaResp as any).error;
      return new Response(JSON.stringify({ ok: true, count_presentations: countPresentations, message: 'Finalisation CIP OK' }), {
        headers: { 'content-type': 'application/json; charset=utf-8', ...corsHeaders },
        status: 200,
      });
    }

    // Import CIP en mode streaming par bytes (stateless): le client fournit byte_offset et carry
    const byteOffset = (body && typeof body.byte_offset === 'number' && body.byte_offset >= 0) ? body.byte_offset as number : 0;
    const maxBytes = (body && typeof body.max_bytes === 'number' && body.max_bytes > 0)
      ? Math.min(256_000, body.max_bytes as number)
      : 64_000;
    const carryIn = (body && typeof body.carry === 'string') ? (body.carry as string) : '';

    const chunk = await loadCipChunk(byteOffset, maxBytes, carryIn);
    const presentations = chunk.rows;

    // Sécurité FK: s'assurer que les CIS référencés existent via requêtes chunkées
    const wantedCis = (() => {
      const s = new Set<number>();
      for (const p of presentations) {
        const v = (p['cis'] as number) || 0;
        if (Number.isFinite(v)) s.add(v);
      }
      return Array.from(s);
    })();

    const existingCis = new Set<number>();
    const chunkSizeCis = 120; // limite URL sûre pour .in() et charge JSON côté client
    for (let i = 0; i < wantedCis.length; i += chunkSizeCis) {
      const endC = Math.min(i + chunkSizeCis, wantedCis.length);
      const chunk = wantedCis.slice(i, endC);
      let resp: any;
      try {
        resp = await supabase
          .from('drugs')
          .select('cis')
          .in('cis', chunk as any);
      } catch (e) {
        throw new Error(`Lecture des CIS existants échouée (chunk ${i}-${endC}): ${(e as Error).message}`);
      }
      if (!resp || typeof resp !== 'object') {
        throw new Error(`Réponse invalide lors de la lecture des CIS (chunk ${i}-${endC})`);
      }
      if (resp.error) {
        throw new Error(`Lecture des CIS existants a renvoyé une erreur (chunk ${i}-${endC}): ${resp.error.message || resp.error}`);
      }
      const rows = Array.isArray(resp.data) ? (resp.data as Array<{ cis: number }>) : [];
      for (const r of rows) {
        const v = Number(r.cis);
        if (Number.isFinite(v)) existingCis.add(v);
      }
    }

    const filtered = presentations.filter((p) => existingCis.has((p['cis'] as number) || -1));
    const skippedMissing = presentations.length - filtered.length;

    // Envoi en petits paquets pour limiter le CPU côté edge (sérialisation JSON)
    await upsertInBatches('presentations', filtered, 'cip13', 200);

    // Réponse chunk: indiquer combien traités et le prochain offset
    const processed = filtered.length;
    const nextByteOffset = chunk.nextByteOffset;
    const nextCarry = chunk.carryOut;
    const payload = {
      ok: true,
      message: processed > 0
        ? `CIP chunk traité: ${processed} (byte_offset=${byteOffset})`
        : 'Aucun enregistrement CIP à traiter pour ce chunk',
      processed,
      skipped_missing_cis: skippedMissing,
      next_byte_offset: nextByteOffset,
      carry: nextCarry,
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

// Démarre le serveur (nécessaire pour répondre correctement, y compris au preflight OPTIONS)
serve(handler);
