-- Escape HTML special characters in existing text fields for safe rich text rendering
-- Only processes fields that haven't been escaped yet (no &lt; present)

UPDATE public.tasks 
SET description = replace(replace(replace(description, '&', '&amp;'), '<', '&lt;'), '>', '&gt;')
WHERE description IS NOT NULL AND description != ''
  AND description NOT LIKE '%&lt;%';

UPDATE public.cases 
SET description = replace(replace(replace(description, '&', '&amp;'), '<', '&lt;'), '>', '&gt;')
WHERE description IS NOT NULL AND description != ''
  AND description NOT LIKE '%&lt;%';

UPDATE public.cases 
SET "internalNotes" = replace(replace(replace("internalNotes", '&', '&amp;'), '<', '&lt;'), '>', '&gt;')
WHERE "internalNotes" IS NOT NULL AND "internalNotes" != ''
  AND "internalNotes" NOT LIKE '%&lt;%';

UPDATE public.clients 
SET observacoes = replace(replace(replace(observacoes, '&', '&amp;'), '<', '&lt;'), '>', '&gt;')
WHERE observacoes IS NOT NULL AND observacoes != ''
  AND observacoes NOT LIKE '%&lt;%';
