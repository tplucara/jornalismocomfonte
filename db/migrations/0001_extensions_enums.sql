-- 0001: extensões, enums e funções utilitárias compartilhadas.
-- Vocabulário (responsabilidade-legal.mdc): nenhum enum ou coluna sugere que a
-- plataforma certifica verdade. Usamos faithful|distorts, valid|rejected, report|opinion.

CREATE EXTENSION IF NOT EXISTS pgcrypto;
CREATE EXTENSION IF NOT EXISTS citext;

-- Identidade
CREATE TYPE journalist_status AS ENUM ('pending_verification', 'verified', 'suspended', 'banned', 'closed');
CREATE TYPE legal_document AS ENUM ('terms', 'privacy', 'content_policy');
CREATE TYPE verification_method AS ENUM ('professional_registry', 'outlet_affiliation', 'portfolio');
CREATE TYPE verification_status AS ENUM ('pending', 'approved', 'rejected');

-- Cadastro de veículos
CREATE TYPE outlet_status AS ENUM ('active', 'suspended', 'removed');
CREATE TYPE outlet_change_action AS ENUM ('included', 'suspended', 'reinstated', 'removed', 'criteria_updated');

-- Conteúdo
CREATE TYPE article_kind AS ENUM ('report', 'analysis', 'opinion');
CREATE TYPE article_status AS ENUM ('draft', 'published', 'removed', 'author_deleted');
CREATE TYPE removal_reason AS ENUM ('court_order', 'valid_notice', 'terms_violation', 'author');
CREATE TYPE source_classification AS ENUM ('report', 'opinion', 'unknown');
CREATE TYPE source_hash_status AS ENUM ('ok', 'changed', 'unavailable');

-- Avaliação
CREATE TYPE fidelity_verdict AS ENUM ('faithful', 'distorts');
CREATE TYPE comment_stance AS ENUM ('agree', 'partially_agree', 'disagree');
CREATE TYPE filter_status AS ENUM ('pending', 'valid', 'rejected');

-- Integridade e legal
CREATE TYPE review_status AS ENUM ('open', 'upheld', 'dismissed');
CREATE TYPE reply_status AS ENUM ('requested', 'published', 'declined');
CREATE TYPE notice_category AS ENUM ('court_order', 'evident_illicit', 'terms_violation');
CREATE TYPE notice_status AS ENUM ('received', 'triage', 'under_review', 'removed', 'denied', 'redirected_to_reply');
CREATE TYPE counter_notice_status AS ENUM ('open', 'reinstated', 'denied');
CREATE TYPE appeal_subject AS ENUM ('vote', 'comment', 'verification', 'source_rejection', 'removal');
CREATE TYPE appeal_status AS ENUM ('open', 'granted', 'denied');

-- Função utilitária: updated_at automático
CREATE OR REPLACE FUNCTION set_updated_at() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
  NEW.updated_at := now();
  RETURN NEW;
END $$;

-- Função utilitária: tabelas append-only (article_versions, legal_acceptances,
-- outlet_changes, audit_log). Nunca UPDATE, nunca DELETE.
CREATE OR REPLACE FUNCTION forbid_update_delete() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
  RAISE EXCEPTION 'append_only_violation: % on % is not allowed', TG_OP, TG_TABLE_NAME
    USING ERRCODE = 'P0001';
END $$;
