-- Migration: Adicionar googleServiceAccount na tabela settings para espelhamento Google Sheets
-- Data: 2026-10-18

ALTER TABLE public.settings
  ADD COLUMN IF NOT EXISTS "googleServiceAccount" TEXT;
