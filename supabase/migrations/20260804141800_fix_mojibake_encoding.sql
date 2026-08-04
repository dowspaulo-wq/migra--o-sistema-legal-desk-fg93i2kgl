-- Migration: Fix double-encoded UTF-8 (Mojibake) in public database tables

CREATE OR REPLACE FUNCTION public.fix_pt_mojibake(txt text)
RETURNS text AS $$
DECLARE
  res text;
BEGIN
  IF txt IS NULL THEN
    RETURN NULL;
  END IF;

  res := txt;
  
  -- Title and common phrase fixes
  res := replace(res, 'PRESTAA‡ÃfO', 'PRESTAÇÃO');
  res := replace(res, 'PRESTAA‡ÃƒO', 'PRESTAÇÃO');
  res := replace(res, 'PRESTAÃ‡Ã̃O', 'PRESTAÇÃO');
  res := replace(res, 'PRESTAÃ‡ÃfO', 'PRESTAÇÃO');
  res := replace(res, 'PRESTAÃ‡Ã£O', 'PRESTAÇÃO');
  res := replace(res, 'SERVIÃ‡OS', 'SERVIÇOS');
  res := replace(res, 'ADVOCATÃI?CIOS', 'ADVOCATÍCIOS');
  res := replace(res, 'ADVOCATÃI\?CIOS', 'ADVOCATÍCIOS');
  res := replace(res, 'ADVOCATÃCIOS', 'ADVOCATÍCIOS');
  res := replace(res, 'ADVOCATÃi?cios', 'advocatícios');
  res := replace(res, 'InterdiÃ§ÃfO', 'Interdição');
  res := replace(res, 'InterdiÃ§Ã̃o', 'Interdição');
  res := replace(res, 'JoÃfO', 'João');
  res := replace(res, 'JoÃ̃o', 'João');
  res := replace(res, 'condiÃ§ÃfUes', 'condições');
  res := replace(res, 'condiÃ§Ã̃es', 'condições');
  res := replace(res, 'prestaÃ§ÃfO', 'prestação');
  res := replace(res, 'prestaÃ§Ã̃o', 'prestação');
  res := replace(res, 'serviÃ§os', 'serviços');

  -- Generic character replacements
  res := replace(res, 'Ã§ÃfO', 'ção');
  res := replace(res, 'Ã§Ã̃o', 'ção');
  res := replace(res, 'Ã§Ã£o', 'ção');
  res := replace(res, 'Ã‡ÃƒO', 'ÇÃO');
  res := replace(res, 'Ã‡Ã̃O', 'ÇÃO');
  res := replace(res, 'Ã§Ãµes', 'ções');
  res := replace(res, 'Ã§', 'ç');
  res := replace(res, 'Ã‡', 'Ç');
  res := replace(res, 'Ã£', 'ã');
  res := replace(res, 'Ã³', 'ó');
  res := replace(res, 'Ã´', 'ô');
  res := replace(res, 'Ãµ', 'õ');
  res := replace(res, 'Ã¡', 'á');
  res := replace(res, 'Ã©', 'é');
  res := replace(res, 'Ãª', 'ê');
  res := replace(res, 'Ã­', 'í');
  res := replace(res, 'Ãº', 'ú');
  res := replace(res, 'Ã¢', 'â');

  RETURN res;
END;
$$ LANGUAGE plpgsql IMMUTABLE;

-- Sanitize document_signatures doc_type
UPDATE public.document_signatures
SET doc_type = public.fix_pt_mojibake(doc_type)
WHERE doc_type LIKE '%Ã%' OR doc_type LIKE '%‡%';

-- Sanitize document_templates name
UPDATE public.document_templates
SET name = public.fix_pt_mojibake(name)
WHERE name LIKE '%Ã%' OR name LIKE '%‡%';

-- Sanitize petitions title & content
UPDATE public.petitions
SET title = public.fix_pt_mojibake(title),
    content = public.fix_pt_mojibake(content)
WHERE title LIKE '%Ã%' OR title LIKE '%‡%' OR content LIKE '%Ã%' OR content LIKE '%‡%';

-- Sanitize cases process_name, description, adverseParty
UPDATE public.cases
SET process_name = public.fix_pt_mojibake(process_name),
    description = public.fix_pt_mojibake(description),
    "adverseParty" = public.fix_pt_mojibake("adverseParty")
WHERE process_name LIKE '%Ã%' OR process_name LIKE '%‡%' 
   OR description LIKE '%Ã%' OR description LIKE '%‡%'
   OR "adverseParty" LIKE '%Ã%' OR "adverseParty" LIKE '%‡%';
