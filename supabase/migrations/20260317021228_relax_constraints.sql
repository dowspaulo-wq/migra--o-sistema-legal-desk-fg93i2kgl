-- Remove NOT NULL constraints to allow optional selection of clients and processes
ALTER TABLE public.appointments ALTER COLUMN "clientId" DROP NOT NULL;
ALTER TABLE public.appointments ALTER COLUMN "processId" DROP NOT NULL;

ALTER TABLE public.tasks ALTER COLUMN "clientId" DROP NOT NULL;
ALTER TABLE public.tasks ALTER COLUMN "relatedProcessId" DROP NOT NULL;
