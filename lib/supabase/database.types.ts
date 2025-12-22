export type Json =
  | string
  | number
  | boolean
  | null
  | { [key: string]: Json | undefined }
  | Json[]

export type Database = {
  // Allows to automatically instantiate createClient with right options
  // instead of createClient<Database, { PostgrestVersion: 'XX' }>(URL, KEY)
  __InternalSupabase: {
    PostgrestVersion: "13.0.5"
  }
  public: {
    Tables: {
      drug_metadata: {
        Row: {
          count_drugs: number | null
          count_presentations: number | null
          id: string
          last_imported_at: string | null
          source: string | null
        }
        Insert: {
          count_drugs?: number | null
          count_presentations?: number | null
          id?: string
          last_imported_at?: string | null
          source?: string | null
        }
        Update: {
          count_drugs?: number | null
          count_presentations?: number | null
          id?: string
          last_imported_at?: string | null
          source?: string | null
        }
        Relationships: []
      }
      drugs: {
        Row: {
          cis: number
          created_at: string
          date_amm: string | null
          denomination: string
          etat_commercialisation: string | null
          forme: string | null
          id: string
          numero_autorisation_europeenne: string | null
          statut_amm: string | null
          statut_bdm: string | null
          surveillance_renforcee: boolean | null
          titulaires: string[] | null
          updated_at: string
          voies: string[] | null
        }
        Insert: {
          cis: number
          created_at?: string
          date_amm?: string | null
          denomination: string
          etat_commercialisation?: string | null
          forme?: string | null
          id?: string
          numero_autorisation_europeenne?: string | null
          statut_amm?: string | null
          statut_bdm?: string | null
          surveillance_renforcee?: boolean | null
          titulaires?: string[] | null
          updated_at?: string
          voies?: string[] | null
        }
        Update: {
          cis?: number
          created_at?: string
          date_amm?: string | null
          denomination?: string
          etat_commercialisation?: string | null
          forme?: string | null
          id?: string
          numero_autorisation_europeenne?: string | null
          statut_amm?: string | null
          statut_bdm?: string | null
          surveillance_renforcee?: boolean | null
          titulaires?: string[] | null
          updated_at?: string
          voies?: string[] | null
        }
        Relationships: []
      }
      families: {
        Row: {
          created_at: string
          created_by: string
          id: string
          invite_code: string | null
          name: string | null
        }
        Insert: {
          created_at?: string
          created_by: string
          id?: string
          invite_code?: string | null
          name?: string | null
        }
        Update: {
          created_at?: string
          created_by?: string
          id?: string
          invite_code?: string | null
          name?: string | null
        }
        Relationships: []
      }
      family_invites: {
        Row: {
          code: string
          created_at: string
          created_by: string
          expires_at: string
          family_id: string
          used_at: string | null
          used_by: string | null
        }
        Insert: {
          code: string
          created_at?: string
          created_by: string
          expires_at?: string
          family_id: string
          used_at?: string | null
          used_by?: string | null
        }
        Update: {
          code?: string
          created_at?: string
          created_by?: string
          expires_at?: string
          family_id?: string
          used_at?: string | null
          used_by?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "family_invites_family_id_fkey"
            columns: ["family_id"]
            isOneToOne: true
            referencedRelation: "families"
            referencedColumns: ["id"]
          },
        ]
      }
      family_members: {
        Row: {
          created_at: string
          family_id: string
          role: string
          user_id: string
        }
        Insert: {
          created_at?: string
          family_id: string
          role?: string
          user_id: string
        }
        Update: {
          created_at?: string
          family_id?: string
          role?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "family_members_family_id_fkey"
            columns: ["family_id"]
            isOneToOne: false
            referencedRelation: "families"
            referencedColumns: ["id"]
          },
        ]
      }
      pharmacy_items: {
        Row: {
          cip13: string
          created_at: string
          family_id: string
          id: string
          quantity: number
          updated_at: string
        }
        Insert: {
          cip13: string
          created_at?: string
          family_id: string
          id?: string
          quantity?: number
          updated_at?: string
        }
        Update: {
          cip13?: string
          created_at?: string
          family_id?: string
          id?: string
          quantity?: number
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "pharmacy_items_family_id_fkey"
            columns: ["family_id"]
            isOneToOne: false
            referencedRelation: "families"
            referencedColumns: ["id"]
          },
        ]
      }
      presentations: {
        Row: {
          cip13: string
          cip7: string | null
          cis: number
          created_at: string
          etat_commercialisation: string | null
          id: string
          libelle: string | null
          prix_euro: number | null
          statut_admin: string | null
          taux_remboursement: string[] | null
          updated_at: string
        }
        Insert: {
          cip13: string
          cip7?: string | null
          cis: number
          created_at?: string
          etat_commercialisation?: string | null
          id?: string
          libelle?: string | null
          prix_euro?: number | null
          statut_admin?: string | null
          taux_remboursement?: string[] | null
          updated_at?: string
        }
        Update: {
          cip13?: string
          cip7?: string | null
          cis?: number
          created_at?: string
          etat_commercialisation?: string | null
          id?: string
          libelle?: string | null
          prix_euro?: number | null
          statut_admin?: string | null
          taux_remboursement?: string[] | null
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "presentations_cis_fkey"
            columns: ["cis"]
            isOneToOne: false
            referencedRelation: "drugs"
            referencedColumns: ["cis"]
          },
        ]
      }
      signup_invites: {
        Row: {
          code: string
          created_at: string
          created_by: string
          email: string | null
          expires_at: string
          role: string
          used_at: string | null
          used_by: string | null
        }
        Insert: {
          code: string
          created_at?: string
          created_by: string
          email?: string | null
          expires_at: string
          role?: string
          used_at?: string | null
          used_by?: string | null
        }
        Update: {
          code?: string
          created_at?: string
          created_by?: string
          email?: string | null
          expires_at?: string
          role?: string
          used_at?: string | null
          used_by?: string | null
        }
        Relationships: []
      }
      users: {
        Row: {
          created_at: string | null
          email: string
          full_name: string | null
          id: string
          role: string
          updated_at: string | null
        }
        Insert: {
          created_at?: string | null
          email: string
          full_name?: string | null
          id: string
          role?: string
          updated_at?: string | null
        }
        Update: {
          created_at?: string | null
          email?: string
          full_name?: string | null
          id?: string
          role?: string
          updated_at?: string | null
        }
        Relationships: []
      }
    }
    Views: {
      [_ in never]: never
    }
    Functions: {
      fn_is_family_member: { Args: { p_family_id: string }; Returns: boolean }
      fn_is_family_owner: { Args: { p_family_id: string }; Returns: boolean }
      rpc_heal_family_state: {
        Args: never
        Returns: {
          family_id: string
        }[]
      }
      rpc_join_family: { Args: { p_code: string }; Returns: string }
      show_limit: { Args: never; Returns: number }
      show_trgm: { Args: { "": string }; Returns: string[] }
    }
    Enums: {
      [_ in never]: never
    }
    CompositeTypes: {
      [_ in never]: never
    }
  }
}

type DatabaseWithoutInternals = Omit<Database, "__InternalSupabase">

type DefaultSchema = DatabaseWithoutInternals[Extract<keyof Database, "public">]

export type Tables<
  DefaultSchemaTableNameOrOptions extends
    | keyof (DefaultSchema["Tables"] & DefaultSchema["Views"])
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"] &
        DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Views"])
    : never = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"] &
      DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Views"])[TableName] extends {
      Row: infer R
    }
    ? R
    : never
  : DefaultSchemaTableNameOrOptions extends keyof (DefaultSchema["Tables"] &
        DefaultSchema["Views"])
    ? (DefaultSchema["Tables"] &
        DefaultSchema["Views"])[DefaultSchemaTableNameOrOptions] extends {
        Row: infer R
      }
      ? R
      : never
    : never

export type TablesInsert<
  DefaultSchemaTableNameOrOptions extends
    | keyof DefaultSchema["Tables"]
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"][TableName] extends {
      Insert: infer I
    }
    ? I
    : never
  : DefaultSchemaTableNameOrOptions extends keyof DefaultSchema["Tables"]
    ? DefaultSchema["Tables"][DefaultSchemaTableNameOrOptions] extends {
        Insert: infer I
      }
      ? I
      : never
    : never

export type TablesUpdate<
  DefaultSchemaTableNameOrOptions extends
    | keyof DefaultSchema["Tables"]
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"][TableName] extends {
      Update: infer U
    }
    ? U
    : never
  : DefaultSchemaTableNameOrOptions extends keyof DefaultSchema["Tables"]
    ? DefaultSchema["Tables"][DefaultSchemaTableNameOrOptions] extends {
        Update: infer U
      }
      ? U
      : never
    : never

export type Enums<
  DefaultSchemaEnumNameOrOptions extends
    | keyof DefaultSchema["Enums"]
    | { schema: keyof DatabaseWithoutInternals },
  EnumName extends DefaultSchemaEnumNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaEnumNameOrOptions["schema"]]["Enums"]
    : never = never,
> = DefaultSchemaEnumNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaEnumNameOrOptions["schema"]]["Enums"][EnumName]
  : DefaultSchemaEnumNameOrOptions extends keyof DefaultSchema["Enums"]
    ? DefaultSchema["Enums"][DefaultSchemaEnumNameOrOptions]
    : never

export type CompositeTypes<
  PublicCompositeTypeNameOrOptions extends
    | keyof DefaultSchema["CompositeTypes"]
    | { schema: keyof DatabaseWithoutInternals },
  CompositeTypeName extends PublicCompositeTypeNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"]
    : never = never,
> = PublicCompositeTypeNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"][CompositeTypeName]
  : PublicCompositeTypeNameOrOptions extends keyof DefaultSchema["CompositeTypes"]
    ? DefaultSchema["CompositeTypes"][PublicCompositeTypeNameOrOptions]
    : never

export const Constants = {
  public: {
    Enums: {},
  },
} as const
