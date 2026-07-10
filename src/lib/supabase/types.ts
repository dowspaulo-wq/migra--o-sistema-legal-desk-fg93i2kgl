// AVOID UPDATING THIS FILE DIRECTLY. It is automatically generated.
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
    PostgrestVersion: "14.4"
  }
  public: {
    Tables: {
      appointments: {
        Row: {
          clientId: string
          created_at: string
          date: string
          description: string | null
          googleEventId: string | null
          id: string
          modality: string | null
          priority: string
          processId: string | null
          responsibleId: string | null
          status: string
          time: string
          title: string
          type: string
          updated_at: string | null
        }
        Insert: {
          clientId: string
          created_at?: string
          date: string
          description?: string | null
          googleEventId?: string | null
          id?: string
          modality?: string | null
          priority?: string
          processId?: string | null
          responsibleId?: string | null
          status?: string
          time?: string
          title: string
          type: string
          updated_at?: string | null
        }
        Update: {
          clientId?: string
          created_at?: string
          date?: string
          description?: string | null
          googleEventId?: string | null
          id?: string
          modality?: string | null
          priority?: string
          processId?: string | null
          responsibleId?: string | null
          status?: string
          time?: string
          title?: string
          type?: string
          updated_at?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "appointments_clientId_fkey"
            columns: ["clientId"]
            isOneToOne: false
            referencedRelation: "clients"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "appointments_processId_fkey"
            columns: ["processId"]
            isOneToOne: false
            referencedRelation: "cases"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "appointments_responsibleId_fkey"
            columns: ["responsibleId"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      case_systems: {
        Row: {
          created_at: string
          id: string
          image_url: string | null
          name: string
        }
        Insert: {
          created_at?: string
          id?: string
          image_url?: string | null
          name: string
        }
        Update: {
          created_at?: string
          id?: string
          image_url?: string | null
          name?: string
        }
        Relationships: []
      }
      cases: {
        Row: {
          adverseParty: string | null
          alerts: string | null
          classification: string | null
          clientId: string | null
          comarca: string | null
          court: string | null
          created_at: string
          description: string | null
          feeInstallments: number | null
          feeType: string | null
          feeValue: number | null
          id: string
          internalNotes: string | null
          isProblematic: boolean
          isSpecial: boolean
          number: string
          parentId: string | null
          position: string | null
          responsibleId: string | null
          startDate: string | null
          state: string | null
          status: string | null
          system: string | null
          type: string | null
          updatedAt: string | null
          value: number
        }
        Insert: {
          adverseParty?: string | null
          alerts?: string | null
          classification?: string | null
          clientId?: string | null
          comarca?: string | null
          court?: string | null
          created_at?: string
          description?: string | null
          feeInstallments?: number | null
          feeType?: string | null
          feeValue?: number | null
          id?: string
          internalNotes?: string | null
          isProblematic?: boolean
          isSpecial?: boolean
          number: string
          parentId?: string | null
          position?: string | null
          responsibleId?: string | null
          startDate?: string | null
          state?: string | null
          status?: string | null
          system?: string | null
          type?: string | null
          updatedAt?: string | null
          value?: number
        }
        Update: {
          adverseParty?: string | null
          alerts?: string | null
          classification?: string | null
          clientId?: string | null
          comarca?: string | null
          court?: string | null
          created_at?: string
          description?: string | null
          feeInstallments?: number | null
          feeType?: string | null
          feeValue?: number | null
          id?: string
          internalNotes?: string | null
          isProblematic?: boolean
          isSpecial?: boolean
          number?: string
          parentId?: string | null
          position?: string | null
          responsibleId?: string | null
          startDate?: string | null
          state?: string | null
          status?: string | null
          system?: string | null
          type?: string | null
          updatedAt?: string | null
          value?: number
        }
        Relationships: [
          {
            foreignKeyName: "cases_clientId_fkey"
            columns: ["clientId"]
            isOneToOne: false
            referencedRelation: "clients"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "cases_parentId_fkey"
            columns: ["parentId"]
            isOneToOne: false
            referencedRelation: "cases"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "cases_responsibleId_fkey"
            columns: ["responsibleId"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      clients: {
        Row: {
          address: string | null
          asaas_id: string | null
          birthday: string | null
          captacao: string | null
          cep: string | null
          city: string | null
          classification: string | null
          complement: string | null
          created_at: string
          document: string | null
          email: string | null
          id: string
          isSpecial: boolean
          marital_status: string | null
          name: string
          neighborhood: string | null
          number: string | null
          observacoes: string | null
          phone: string | null
          responsibleId: string | null
          state: string | null
          status: string
          street: string | null
          type: string
        }
        Insert: {
          address?: string | null
          asaas_id?: string | null
          birthday?: string | null
          captacao?: string | null
          cep?: string | null
          city?: string | null
          classification?: string | null
          complement?: string | null
          created_at?: string
          document?: string | null
          email?: string | null
          id?: string
          isSpecial?: boolean
          marital_status?: string | null
          name: string
          neighborhood?: string | null
          number?: string | null
          observacoes?: string | null
          phone?: string | null
          responsibleId?: string | null
          state?: string | null
          status?: string
          street?: string | null
          type: string
        }
        Update: {
          address?: string | null
          asaas_id?: string | null
          birthday?: string | null
          captacao?: string | null
          cep?: string | null
          city?: string | null
          classification?: string | null
          complement?: string | null
          created_at?: string
          document?: string | null
          email?: string | null
          id?: string
          isSpecial?: boolean
          marital_status?: string | null
          name?: string
          neighborhood?: string | null
          number?: string | null
          observacoes?: string | null
          phone?: string | null
          responsibleId?: string | null
          state?: string | null
          status?: string
          street?: string | null
          type?: string
        }
        Relationships: [
          {
            foreignKeyName: "clients_responsibleId_fkey"
            columns: ["responsibleId"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      logs: {
        Row: {
          action: string
          created_at: string
          date: string
          details: string | null
          entity: string
          id: string
          user: string
        }
        Insert: {
          action: string
          created_at?: string
          date: string
          details?: string | null
          entity: string
          id?: string
          user: string
        }
        Update: {
          action?: string
          created_at?: string
          date?: string
          details?: string | null
          entity?: string
          id?: string
          user?: string
        }
        Relationships: []
      }
      petitions: {
        Row: {
          category: string
          content: string
          created_at: string
          id: string
          title: string
        }
        Insert: {
          category: string
          content: string
          created_at?: string
          id?: string
          title: string
        }
        Update: {
          category?: string
          content?: string
          created_at?: string
          id?: string
          title?: string
        }
        Relationships: []
      }
      profiles: {
        Row: {
          avatar_url: string | null
          canViewFinance: boolean
          color: string
          created_at: string
          email: string | null
          id: string
          name: string
          role: string
        }
        Insert: {
          avatar_url?: string | null
          canViewFinance?: boolean
          color?: string
          created_at?: string
          email?: string | null
          id: string
          name: string
          role?: string
        }
        Update: {
          avatar_url?: string | null
          canViewFinance?: boolean
          color?: string
          created_at?: string
          email?: string | null
          id?: string
          name?: string
          role?: string
        }
        Relationships: []
      }
      settings: {
        Row: {
          appointmentTypes: Json | null
          bankAccounts: Json | null
          captacaoOptions: Json | null
          caseStatuses: Json | null
          caseTypes: Json | null
          clientPositions: Json | null
          created_at: string
          googleCalendarTokens: Json | null
          id: string
          logoUrl: string | null
          showFinanceDashboard: boolean
          taskStatuses: Json | null
          taskTypes: Json | null
          themeColor: string
        }
        Insert: {
          appointmentTypes?: Json | null
          bankAccounts?: Json | null
          captacaoOptions?: Json | null
          caseStatuses?: Json | null
          caseTypes?: Json | null
          clientPositions?: Json | null
          created_at?: string
          googleCalendarTokens?: Json | null
          id?: string
          logoUrl?: string | null
          showFinanceDashboard?: boolean
          taskStatuses?: Json | null
          taskTypes?: Json | null
          themeColor?: string
        }
        Update: {
          appointmentTypes?: Json | null
          bankAccounts?: Json | null
          captacaoOptions?: Json | null
          caseStatuses?: Json | null
          caseTypes?: Json | null
          clientPositions?: Json | null
          created_at?: string
          googleCalendarTokens?: Json | null
          id?: string
          logoUrl?: string | null
          showFinanceDashboard?: boolean
          taskStatuses?: Json | null
          taskTypes?: Json | null
          themeColor?: string
        }
        Relationships: []
      }
      suppliers: {
        Row: {
          created_at: string
          document: string | null
          email: string | null
          id: string
          name: string
          phone: string | null
          status: string | null
        }
        Insert: {
          created_at?: string
          document?: string | null
          email?: string | null
          id?: string
          name: string
          phone?: string | null
          status?: string | null
        }
        Update: {
          created_at?: string
          document?: string | null
          email?: string | null
          id?: string
          name?: string
          phone?: string | null
          status?: string | null
        }
        Relationships: []
      }
      tasks: {
        Row: {
          clientId: string | null
          created_at: string
          description: string | null
          dueDate: string | null
          id: string
          internalNotes: string | null
          priority: string
          relatedProcessId: string | null
          responsibleId: string | null
          status: string
          title: string
          type: string
        }
        Insert: {
          clientId?: string | null
          created_at?: string
          description?: string | null
          dueDate?: string | null
          id?: string
          internalNotes?: string | null
          priority?: string
          relatedProcessId?: string | null
          responsibleId?: string | null
          status?: string
          title: string
          type?: string
        }
        Update: {
          clientId?: string | null
          created_at?: string
          description?: string | null
          dueDate?: string | null
          id?: string
          internalNotes?: string | null
          priority?: string
          relatedProcessId?: string | null
          responsibleId?: string | null
          status?: string
          title?: string
          type?: string
        }
        Relationships: [
          {
            foreignKeyName: "tasks_clientId_fkey"
            columns: ["clientId"]
            isOneToOne: false
            referencedRelation: "clients"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "tasks_relatedProcessId_fkey"
            columns: ["relatedProcessId"]
            isOneToOne: false
            referencedRelation: "cases"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "tasks_responsibleId_fkey"
            columns: ["responsibleId"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      transaction_cases: {
        Row: {
          case_id: string
          created_at: string
          id: string
          transaction_id: string
        }
        Insert: {
          case_id: string
          created_at?: string
          id?: string
          transaction_id: string
        }
        Update: {
          case_id?: string
          created_at?: string
          id?: string
          transaction_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "transaction_cases_case_id_fkey"
            columns: ["case_id"]
            isOneToOne: false
            referencedRelation: "cases"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "transaction_cases_transaction_id_fkey"
            columns: ["transaction_id"]
            isOneToOne: false
            referencedRelation: "transactions"
            referencedColumns: ["id"]
          },
        ]
      }
      transactions: {
        Row: {
          amount: number
          asaas_id: string | null
          bankAccount: string | null
          category: string
          clientId: string | null
          created_at: string
          date: string
          description: string
          id: string
          payment_method: string | null
          processId: string | null
          sendToFinance: boolean | null
          status: string
          supplierId: string | null
          type: string
        }
        Insert: {
          amount?: number
          asaas_id?: string | null
          bankAccount?: string | null
          category: string
          clientId?: string | null
          created_at?: string
          date: string
          description: string
          id?: string
          payment_method?: string | null
          processId?: string | null
          sendToFinance?: boolean | null
          status: string
          supplierId?: string | null
          type: string
        }
        Update: {
          amount?: number
          asaas_id?: string | null
          bankAccount?: string | null
          category?: string
          clientId?: string | null
          created_at?: string
          date?: string
          description?: string
          id?: string
          payment_method?: string | null
          processId?: string | null
          sendToFinance?: boolean | null
          status?: string
          supplierId?: string | null
          type?: string
        }
        Relationships: [
          {
            foreignKeyName: "transactions_clientId_fkey"
            columns: ["clientId"]
            isOneToOne: false
            referencedRelation: "clients"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "transactions_processId_fkey"
            columns: ["processId"]
            isOneToOne: false
            referencedRelation: "cases"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "transactions_supplierId_fkey"
            columns: ["supplierId"]
            isOneToOne: false
            referencedRelation: "suppliers"
            referencedColumns: ["id"]
          },
        ]
      }
      whatsapp_messages: {
        Row: {
          contact_name: string
          created_at: string
          direction: string
          id: string
          message: string
          phone: string
        }
        Insert: {
          contact_name: string
          created_at?: string
          direction: string
          id?: string
          message: string
          phone: string
        }
        Update: {
          contact_name?: string
          created_at?: string
          direction?: string
          id?: string
          message?: string
          phone?: string
        }
        Relationships: []
      }
    }
    Views: {
      [_ in never]: never
    }
    Functions: {
      [_ in never]: never
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

