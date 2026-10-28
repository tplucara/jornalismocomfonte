-- 0012: sessão server-side do jornalista (stack-e-seguranca.mdc).
-- O cookie leva só o token. O dado da sessão fica aqui, opaco.
-- DELETE é permitido nesta tabela: encerrar a sessão e apagar token vencido
-- não é apagar conteúdo. As demais tabelas continuam sem DELETE para jcf_web.

CREATE TABLE sessions (
  token   text PRIMARY KEY,
  data    bytea NOT NULL,
  expiry  timestamptz NOT NULL
);

CREATE INDEX sessions_expiry_idx ON sessions (expiry);

GRANT SELECT, INSERT, UPDATE, DELETE ON sessions TO jcf_web_role;
