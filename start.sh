docker run --rm --name postgraphile-example -e POSTGRES_PASSWORD=secret -p 5432:5432 -d postgres:10-alpine
sleep 5
psql -h 127.0.0.1 -p 5432 -U postgres postgres < app.sql
psql -h 127.0.0.1 -p 5432 -U postgres postgres < seed.sql
sleep 1
postgraphile \
  --schema app,app_private \
  --connection postgres://postgres:secret@127.0.0.1:5432/postgres \
  --default-role app_anonymous \
  --jwt-token-identifier app.jwt_token \
  --jwt-secret app_example
