// AVOID UPDATING THIS FILE DIRECTLY. It is automatically generated.
export type Json = string | number | boolean | null | { [key: string]: Json | undefined } | Json[]

export type Database = {
  // Allows to automatically instantiate createClient with right options
  // instead of createClient<Database, { PostgrestVersion: 'XX' }>(URL, KEY)
  __InternalSupabase: {
    PostgrestVersion: '14.4'
  }
  public: {
    Tables: {
      appointments: {
        Row: {
          clientId: string
          created_at: string
          date: string
          description: string | null
          id: string
          priority: string
          processId: string
          responsibleId: string | null
          time: string
          title: string
          type: string
        }
        Insert: {
          clientId: string
          created_at?: string
          date: string
          description?: string | null
          id?: string
          priority?: string
          processId: string
          responsibleId?: string | null
          time?: string
          title: string
          type: string
        }
        Update: {
          clientId?: string
          created_at?: string
          date?: string
          description?: string | null
          id?: string
          priority?: string
          processId?: string
          responsibleId?: string | null
          time?: string
          title?: string
          type?: string
        }
        Relationships: [
          {
            foreignKeyName: 'appointments_clientId_fkey'
            columns: ['clientId']
            isOneToOne: false
            referencedRelation: 'clients'
            referencedColumns: ['id']
          },
          {
            foreignKeyName: 'appointments_processId_fkey'
            columns: ['processId']
            isOneToOne: false
            referencedRelation: 'cases'
            referencedColumns: ['id']
          },
          {
            foreignKeyName: 'appointments_responsibleId_fkey'
            columns: ['responsibleId']
            isOneToOne: false
            referencedRelation: 'profiles'
            referencedColumns: ['id']
          },
        ]
      }
      cases: {
        Row: {
          adverseParty: string | null
          alerts: string | null
          clientId: string | null
          comarca: string | null
          court: string | null
          created_at: string
          description: string | null
          id: string
          internalNotes: string | null
          isSpecial: boolean
          number: string
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
          clientId?: string | null
          comarca?: string | null
          court?: string | null
          created_at?: string
          description?: string | null
          id?: string
          internalNotes?: string | null
          isSpecial?: boolean
          number: string
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
          clientId?: string | null
          comarca?: string | null
          court?: string | null
          created_at?: string
          description?: string | null
          id?: string
          internalNotes?: string | null
          isSpecial?: boolean
          number?: string
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
            foreignKeyName: 'cases_clientId_fkey'
            columns: ['clientId']
            isOneToOne: false
            referencedRelation: 'clients'
            referencedColumns: ['id']
          },
          {
            foreignKeyName: 'cases_responsibleId_fkey'
            columns: ['responsibleId']
            isOneToOne: false
            referencedRelation: 'profiles'
            referencedColumns: ['id']
          },
        ]
      }
      clients: {
        Row: {
          address: string | null
          birthday: string | null
          created_at: string
          document: string
          email: string | null
          id: string
          isSpecial: boolean
          name: string
          observacoes: string | null
          phone: string | null
          responsibleId: string | null
          status: string
          type: string
        }
        Insert: {
          address?: string | null
          birthday?: string | null
          created_at?: string
          document: string
          email?: string | null
          id?: string
          isSpecial?: boolean
          name: string
          observacoes?: string | null
          phone?: string | null
          responsibleId?: string | null
          status?: string
          type: string
        }
        Update: {
          address?: string | null
          birthday?: string | null
          created_at?: string
          document?: string
          email?: string | null
          id?: string
          isSpecial?: boolean
          name?: string
          observacoes?: string | null
          phone?: string | null
          responsibleId?: string | null
          status?: string
          type?: string
        }
        Relationships: [
          {
            foreignKeyName: 'clients_responsibleId_fkey'
            columns: ['responsibleId']
            isOneToOne: false
            referencedRelation: 'profiles'
            referencedColumns: ['id']
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
          canViewFinance: boolean
          color: string
          created_at: string
          email: string | null
          id: string
          name: string
          role: string
        }
        Insert: {
          canViewFinance?: boolean
          color?: string
          created_at?: string
          email?: string | null
          id: string
          name: string
          role?: string
        }
        Update: {
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
          caseStatuses: Json | null
          caseTypes: Json | null
          created_at: string
          id: string
          logoUrl: string | null
          showFinanceDashboard: boolean
          taskStatuses: Json | null
          taskTypes: Json | null
          themeColor: string
        }
        Insert: {
          appointmentTypes?: Json | null
          caseStatuses?: Json | null
          caseTypes?: Json | null
          created_at?: string
          id?: string
          logoUrl?: string | null
          showFinanceDashboard?: boolean
          taskStatuses?: Json | null
          taskTypes?: Json | null
          themeColor?: string
        }
        Update: {
          appointmentTypes?: Json | null
          caseStatuses?: Json | null
          caseTypes?: Json | null
          created_at?: string
          id?: string
          logoUrl?: string | null
          showFinanceDashboard?: boolean
          taskStatuses?: Json | null
          taskTypes?: Json | null
          themeColor?: string
        }
        Relationships: []
      }
      tasks: {
        Row: {
          clientId: string
          created_at: string
          description: string | null
          dueDate: string | null
          id: string
          internalNotes: string | null
          priority: string
          relatedProcessId: string
          responsibleId: string | null
          status: string
          title: string
          type: string
        }
        Insert: {
          clientId: string
          created_at?: string
          description?: string | null
          dueDate?: string | null
          id?: string
          internalNotes?: string | null
          priority?: string
          relatedProcessId: string
          responsibleId?: string | null
          status?: string
          title: string
          type?: string
        }
        Update: {
          clientId?: string
          created_at?: string
          description?: string | null
          dueDate?: string | null
          id?: string
          internalNotes?: string | null
          priority?: string
          relatedProcessId?: string
          responsibleId?: string | null
          status?: string
          title?: string
          type?: string
        }
        Relationships: [
          {
            foreignKeyName: 'tasks_clientId_fkey'
            columns: ['clientId']
            isOneToOne: false
            referencedRelation: 'clients'
            referencedColumns: ['id']
          },
          {
            foreignKeyName: 'tasks_relatedProcessId_fkey'
            columns: ['relatedProcessId']
            isOneToOne: false
            referencedRelation: 'cases'
            referencedColumns: ['id']
          },
          {
            foreignKeyName: 'tasks_responsibleId_fkey'
            columns: ['responsibleId']
            isOneToOne: false
            referencedRelation: 'profiles'
            referencedColumns: ['id']
          },
        ]
      }
      transactions: {
        Row: {
          amount: number
          category: string
          clientId: string | null
          created_at: string
          date: string
          description: string
          id: string
          processId: string | null
          status: string
          type: string
        }
        Insert: {
          amount?: number
          category: string
          clientId?: string | null
          created_at?: string
          date: string
          description: string
          id?: string
          processId?: string | null
          status: string
          type: string
        }
        Update: {
          amount?: number
          category?: string
          clientId?: string | null
          created_at?: string
          date?: string
          description?: string
          id?: string
          processId?: string | null
          status?: string
          type?: string
        }
        Relationships: [
          {
            foreignKeyName: 'transactions_clientId_fkey'
            columns: ['clientId']
            isOneToOne: false
            referencedRelation: 'clients'
            referencedColumns: ['id']
          },
          {
            foreignKeyName: 'transactions_processId_fkey'
            columns: ['processId']
            isOneToOne: false
            referencedRelation: 'cases'
            referencedColumns: ['id']
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

type DatabaseWithoutInternals = Omit<Database, '__InternalSupabase'>

type DefaultSchema = DatabaseWithoutInternals[Extract<keyof Database, 'public'>]

export type Tables<
  DefaultSchemaTableNameOrOptions extends
    | keyof (DefaultSchema['Tables'] & DefaultSchema['Views'])
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions['schema']]['Tables'] &
        DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions['schema']]['Views'])
    : never = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions['schema']]['Tables'] &
      DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions['schema']]['Views'])[TableName] extends {
      Row: infer R
    }
    ? R
    : never
  : DefaultSchemaTableNameOrOptions extends keyof (DefaultSchema['Tables'] & DefaultSchema['Views'])
    ? (DefaultSchema['Tables'] & DefaultSchema['Views'])[DefaultSchemaTableNameOrOptions] extends {
        Row: infer R
      }
      ? R
      : never
    : never

export type TablesInsert<
  DefaultSchemaTableNameOrOptions extends
    | keyof DefaultSchema['Tables']
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions['schema']]['Tables']
    : never = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions['schema']]['Tables'][TableName] extends {
      Insert: infer I
    }
    ? I
    : never
  : DefaultSchemaTableNameOrOptions extends keyof DefaultSchema['Tables']
    ? DefaultSchema['Tables'][DefaultSchemaTableNameOrOptions] extends {
        Insert: infer I
      }
      ? I
      : never
    : never

export type TablesUpdate<
  DefaultSchemaTableNameOrOptions extends
    | keyof DefaultSchema['Tables']
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions['schema']]['Tables']
    : never = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions['schema']]['Tables'][TableName] extends {
      Update: infer U
    }
    ? U
    : never
  : DefaultSchemaTableNameOrOptions extends keyof DefaultSchema['Tables']
    ? DefaultSchema['Tables'][DefaultSchemaTableNameOrOptions] extends {
        Update: infer U
      }
      ? U
      : never
    : never

export type Enums<
  DefaultSchemaEnumNameOrOptions extends
    | keyof DefaultSchema['Enums']
    | { schema: keyof DatabaseWithoutInternals },
  EnumName extends DefaultSchemaEnumNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaEnumNameOrOptions['schema']]['Enums']
    : never = never,
> = DefaultSchemaEnumNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaEnumNameOrOptions['schema']]['Enums'][EnumName]
  : DefaultSchemaEnumNameOrOptions extends keyof DefaultSchema['Enums']
    ? DefaultSchema['Enums'][DefaultSchemaEnumNameOrOptions]
    : never

export type CompositeTypes<
  PublicCompositeTypeNameOrOptions extends
    | keyof DefaultSchema['CompositeTypes']
    | { schema: keyof DatabaseWithoutInternals },
  CompositeTypeName extends PublicCompositeTypeNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions['schema']]['CompositeTypes']
    : never = never,
> = PublicCompositeTypeNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions['schema']]['CompositeTypes'][CompositeTypeName]
  : PublicCompositeTypeNameOrOptions extends keyof DefaultSchema['CompositeTypes']
    ? DefaultSchema['CompositeTypes'][PublicCompositeTypeNameOrOptions]
    : never

export const Constants = {
  public: {
    Enums: {},
  },
} as const

// ====== DATABASE EXTENDED CONTEXT (auto-generated) ======
// This section contains actual PostgreSQL column types, constraints, RLS policies,
// functions, triggers, indexes and materialized views not present in the type definitions above.
// IMPORTANT: The TypeScript types above map UUID, TEXT, VARCHAR all to "string".
// Use the COLUMN TYPES section below to know the real PostgreSQL type for each column.
// Always use the correct PostgreSQL type when writing SQL migrations.

// --- COLUMN TYPES (actual PostgreSQL types) ---
// Use this to know the real database type when writing migrations.
// "string" in TypeScript types above may be uuid, text, varchar, timestamptz, etc.
// Table: appointments
//   id: uuid (not null, default: gen_random_uuid())
//   title: text (not null)
//   date: text (not null)
//   type: text (not null)
//   responsibleId: uuid (nullable)
//   clientId: uuid (not null)
//   processId: uuid (not null)
//   created_at: timestamp with time zone (not null, default: now())
//   priority: text (not null, default: 'Média'::text)
//   time: text (not null, default: '00:00'::text)
//   description: text (nullable)
// Table: cases
//   id: uuid (not null, default: gen_random_uuid())
//   clientId: uuid (nullable)
//   number: text (not null)
//   position: text (nullable)
//   adverseParty: text (nullable)
//   type: text (nullable)
//   status: text (nullable)
//   court: text (nullable)
//   comarca: text (nullable)
//   state: text (nullable)
//   system: text (nullable)
//   value: numeric (not null, default: 0)
//   startDate: text (nullable)
//   responsibleId: uuid (nullable)
//   updatedAt: text (nullable)
//   created_at: timestamp with time zone (not null, default: now())
//   isSpecial: boolean (not null, default: false)
//   description: text (nullable)
//   internalNotes: text (nullable)
//   alerts: text (nullable)
// Table: clients
//   id: uuid (not null, default: gen_random_uuid())
//   name: text (not null)
//   document: text (not null)
//   type: text (not null)
//   email: text (nullable)
//   phone: text (nullable)
//   address: text (nullable)
//   birthday: text (nullable)
//   responsibleId: uuid (nullable)
//   status: text (not null, default: 'Ativo'::text)
//   isSpecial: boolean (not null, default: false)
//   created_at: timestamp with time zone (not null, default: now())
//   observacoes: text (nullable)
// Table: logs
//   id: uuid (not null, default: gen_random_uuid())
//   action: text (not null)
//   entity: text (not null)
//   user: text (not null)
//   date: text (not null)
//   details: text (nullable)
//   created_at: timestamp with time zone (not null, default: now())
// Table: petitions
//   id: uuid (not null, default: gen_random_uuid())
//   title: text (not null)
//   content: text (not null)
//   category: text (not null)
//   created_at: timestamp with time zone (not null, default: now())
// Table: profiles
//   id: uuid (not null)
//   name: text (not null)
//   role: text (not null, default: 'User'::text)
//   canViewFinance: boolean (not null, default: false)
//   color: text (not null, default: '#3b82f6'::text)
//   created_at: timestamp with time zone (not null, default: now())
//   email: text (nullable)
// Table: settings
//   id: uuid (not null, default: gen_random_uuid())
//   showFinanceDashboard: boolean (not null, default: true)
//   themeColor: text (not null, default: 'blue'::text)
//   logoUrl: text (nullable)
//   created_at: timestamp with time zone (not null, default: now())
//   caseStatuses: jsonb (nullable, default: '["Em andamento", "Pendente", "Concluído", "Arquivado"]'::jsonb)
//   caseTypes: jsonb (nullable, default: '["Cível", "Trabalhista", "Tributário", "Criminal", "Família"]'::jsonb)
//   appointmentTypes: jsonb (nullable, default: '["Reunião", "Aud.conciliação", "Diligência", "Feriado", "Outro"]'::jsonb)
//   taskStatuses: jsonb (nullable, default: '["em andamento", "pendente", "atualização", "Concluída", "aguarda protocolo", "cancelada"]'::jsonb)
//   taskTypes: jsonb (nullable, default: '["Cartórios", "Petições", "Recorrer", "Redigir inicial", "interna e adm"]'::jsonb)
// Table: tasks
//   id: uuid (not null, default: gen_random_uuid())
//   title: text (not null)
//   description: text (nullable)
//   dueDate: text (nullable)
//   status: text (not null, default: 'Pendente'::text)
//   priority: text (not null, default: 'Média'::text)
//   responsibleId: uuid (nullable)
//   relatedProcessId: uuid (not null)
//   created_at: timestamp with time zone (not null, default: now())
//   type: text (not null, default: 'Outro'::text)
//   clientId: uuid (not null)
//   internalNotes: text (nullable)
// Table: transactions
//   id: uuid (not null, default: gen_random_uuid())
//   description: text (not null)
//   amount: numeric (not null, default: 0)
//   type: text (not null)
//   category: text (not null)
//   status: text (not null)
//   date: text (not null)
//   clientId: uuid (nullable)
//   processId: uuid (nullable)
//   created_at: timestamp with time zone (not null, default: now())
// Table: whatsapp_messages
//   id: uuid (not null, default: gen_random_uuid())
//   phone: text (not null)
//   contact_name: text (not null)
//   message: text (not null)
//   direction: text (not null)
//   created_at: timestamp with time zone (not null, default: now())

// --- CONSTRAINTS ---
// Table: appointments
//   FOREIGN KEY appointments_clientId_fkey: FOREIGN KEY ("clientId") REFERENCES clients(id) ON DELETE CASCADE
//   PRIMARY KEY appointments_pkey: PRIMARY KEY (id)
//   FOREIGN KEY appointments_processId_fkey: FOREIGN KEY ("processId") REFERENCES cases(id) ON DELETE CASCADE
//   FOREIGN KEY appointments_responsibleId_fkey: FOREIGN KEY ("responsibleId") REFERENCES profiles(id)
// Table: cases
//   FOREIGN KEY cases_clientId_fkey: FOREIGN KEY ("clientId") REFERENCES clients(id) ON DELETE CASCADE
//   UNIQUE cases_number_key: UNIQUE (number)
//   PRIMARY KEY cases_pkey: PRIMARY KEY (id)
//   FOREIGN KEY cases_responsibleId_fkey: FOREIGN KEY ("responsibleId") REFERENCES profiles(id)
// Table: clients
//   UNIQUE clients_document_key: UNIQUE (document)
//   PRIMARY KEY clients_pkey: PRIMARY KEY (id)
//   FOREIGN KEY clients_responsibleId_fkey: FOREIGN KEY ("responsibleId") REFERENCES profiles(id)
// Table: logs
//   PRIMARY KEY logs_pkey: PRIMARY KEY (id)
// Table: petitions
//   PRIMARY KEY petitions_pkey: PRIMARY KEY (id)
// Table: profiles
//   FOREIGN KEY profiles_id_fkey: FOREIGN KEY (id) REFERENCES auth.users(id) ON DELETE CASCADE
//   PRIMARY KEY profiles_pkey: PRIMARY KEY (id)
// Table: settings
//   PRIMARY KEY settings_pkey: PRIMARY KEY (id)
// Table: tasks
//   FOREIGN KEY tasks_clientId_fkey: FOREIGN KEY ("clientId") REFERENCES clients(id) ON DELETE CASCADE
//   PRIMARY KEY tasks_pkey: PRIMARY KEY (id)
//   FOREIGN KEY tasks_relatedProcessId_fkey: FOREIGN KEY ("relatedProcessId") REFERENCES cases(id) ON DELETE CASCADE
//   FOREIGN KEY tasks_responsibleId_fkey: FOREIGN KEY ("responsibleId") REFERENCES profiles(id)
// Table: transactions
//   FOREIGN KEY transactions_clientId_fkey: FOREIGN KEY ("clientId") REFERENCES clients(id) ON DELETE CASCADE
//   PRIMARY KEY transactions_pkey: PRIMARY KEY (id)
//   FOREIGN KEY transactions_processId_fkey: FOREIGN KEY ("processId") REFERENCES cases(id) ON DELETE CASCADE
// Table: whatsapp_messages
//   PRIMARY KEY whatsapp_messages_pkey: PRIMARY KEY (id)

// --- DATABASE FUNCTIONS ---
// FUNCTION handle_new_case_task()
//   CREATE OR REPLACE FUNCTION public.handle_new_case_task()
//    RETURNS trigger
//    LANGUAGE plpgsql
//    SECURITY DEFINER
//   AS $function$
//   DECLARE
//       next_month date;
//       due_date text;
//       internal_task_type text := 'interna e adm';
//   BEGIN
//       next_month := (date_trunc('month', NEW.created_at) + interval '1 month')::date;
//       due_date := to_char(next_month + interval '24 days', 'YYYY-MM-DD');
//
//       INSERT INTO public.tasks (
//           title,
//           "clientId",
//           "relatedProcessId",
//           status,
//           priority,
//           type,
//           "dueDate",
//           "responsibleId"
//       ) VALUES (
//           'Atualização de Processo - ' || NEW.number,
//           NEW."clientId",
//           NEW.id,
//           'atualização',
//           'Média',
//           internal_task_type,
//           due_date,
//           NEW."responsibleId"
//       );
//
//       RETURN NEW;
//   END;
//   $function$
//
// FUNCTION handle_new_user()
//   CREATE OR REPLACE FUNCTION public.handle_new_user()
//    RETURNS trigger
//    LANGUAGE plpgsql
//    SECURITY DEFINER
//   AS $function$
//   BEGIN
//     INSERT INTO public.profiles (id, email, name, role, "canViewFinance", color)
//     VALUES (
//       NEW.id,
//       NEW.email,
//       COALESCE(NEW.raw_user_meta_data->>'name', 'Usuário'),
//       COALESCE(NEW.raw_user_meta_data->>'role', 'User'),
//       COALESCE((NEW.raw_user_meta_data->>'canViewFinance')::boolean, false),
//       COALESCE(NEW.raw_user_meta_data->>'color', '#3b82f6')
//     );
//     RETURN NEW;
//   END;
//   $function$
//

// --- TRIGGERS ---
// Table: cases
//   on_case_created: CREATE TRIGGER on_case_created AFTER INSERT ON public.cases FOR EACH ROW EXECUTE FUNCTION handle_new_case_task()

// --- INDEXES ---
// Table: cases
//   CREATE UNIQUE INDEX cases_number_key ON public.cases USING btree (number)
// Table: clients
//   CREATE UNIQUE INDEX clients_document_key ON public.clients USING btree (document)
