begin;




create extension if not exists "pgcrypto";
create extension if not exists "uuid-ossp";


create schema app;
create schema app_private;


-- table app.person
create table app.person (
  --id               uuid primary key default uuid_generate_v1mc(),
  id               serial primary key,
  first_name       text not null check (char_length(first_name) < 80),
  last_name        text check (char_length(last_name) < 80),
  about            text,
  created_at       timestamp default now(),
  updated_at       timestamp default now()
);
comment on table app.person is
  'A user of the forum.';
comment on column app.person.id is
  'The primary unique identifier for the person.';
comment on column app.person.first_name is
  'The person’s first name.';
comment on column app.person.last_name is
  'The person’s last name.';
comment on column app.person.about is
  'A short description about the user, written by the user.';
comment on column app.person.created_at is
  'The time this person was created.';


-- type app.post_topic
create type app.post_topic as enum (
  'discussion',
  'inspiration',
  'help',
  'showcase'
);


-- table app.post
create table app.post (
  id               serial primary key,
  author_id        integer not null references app.person(id),
  headline         text not null check (char_length(headline) < 280),
  body             text,
  topic            app.post_topic,
  created_at       timestamp default now(),
  updated_at       timestamp default now()
);
comment on table app.post is
  'A forum post written by a user.';
comment on column app.post.id is
  'The primary key for the post.';
comment on column app.post.headline is
  'The title written by the user.';
comment on column app.post.author_id is
  'The id of the author user.';
comment on column app.post.topic is
  'The topic this has been posted in.';
comment on column app.post.body is
  'The main body text of our post.';
comment on column app.post.created_at is
  'The time this post was created.';


-- function app.person_full_name
create function app.person_full_name(person app.person) returns text as $$
  select person.first_name || ' ' || person.last_name
$$ language sql stable;
comment on function app.person_full_name(app.person) is
  'A person’s full name which is a concatenation of their first and last name.';


-- function app.post_summary
create function app.post_summary (
  post app.post,
  length int default 50,
  omission text default '…'
) returns text as $$
  select case
    when post.body is null then null
    else substr(post.body, 0, length) || omission
  end
$$ language sql stable;
comment on function app.post_summary(app.post, int, text) is
  'A truncated version of the body for summaries.';

-- function app.person_latest_post
create function app.person_latest_post(person app.person) returns app.post as $$
  select post.*
  from app.post as post
  where post.author_id = person.id
  order by created_at desc
  limit 1
$$ language sql stable;
comment on function app.person_latest_post(app.person) is
  'Get’s the latest post written by the person.';


-- function app.search_posts
create function app.search_posts(search text) returns setof app.post as $$
  select post.*
  from app.post as post
  where post.headline ilike ('%' || search || '%') or post.body ilike ('%' || search || '%')
$$ language sql stable;
comment on function app.search_posts(text) is
  'Returns posts containing a given search term.';


-- function app_private.set_updated_at
create function app_private.set_updated_at() returns trigger as $$
begin
  new.updated_at := current_timestamp;
  return new;
end;
$$ language plpgsql;


-- trigger person_updated_at
create trigger person_updated_at before update
  on app.person
  for each row
  execute procedure app_private.set_updated_at();


-- trigger post_updated_at
create trigger post_updated_at before update
  on app.post
  for each row
  execute procedure app_private.set_updated_at();


-- table app_private.person_account
create table app_private.person_account (
  person_id        integer primary key references app.person(id) on delete cascade,
  email            text not null unique check (email ~* '^.+@.+\..+$'),
  password_hash    text not null
);
comment on table app_private.person_account is
  'Private information about a person’s account.';
comment on column app_private.person_account.person_id is
  'The id of the person associated with this account.';
comment on column app_private.person_account.email is
  'The email address of the person.';
comment on column app_private.person_account.password_hash is
  'An opaque hash of the person’s password.';


-- function app.register_person
create function app.register_person(
  first_name text,
  last_name text,
  email text,
  password text
) returns app.person as $$
declare
  person app.person;
begin
  insert into app.person (first_name, last_name) values
    (first_name, last_name)
    returning * into person;

  insert into app_private.person_account (person_id, email, password_hash) values
    (person.id, email, crypt(password, gen_salt('bf')));

  return person;
end;
$$ language plpgsql strict security definer;
comment on function app.register_person(text, text, text, text) is
  'Registers a single user and creates an account in our forum.';


-- role app_postgraphile
create role app_postgraphile login password 'secret';


-- role app_anonymous
create role app_anonymous;
grant app_anonymous to app_postgraphile;


-- role app_person
create role app_person;
grant app_person to app_postgraphile;


-- type app.jwt_token
create type app.jwt_token as (
  role text,
  person_id integer
);


-- function app.authenticate
create function app.authenticate(
  email text,
  password text
) returns app.jwt_token as $$
declare
  account app_private.person_account;
begin
  select a.* into account
  from app_private.person_account as a
  where a.email = $1;

  if account.password_hash = crypt(password, account.password_hash) then
    return ('app_person', account.person_id)::app.jwt_token;
  else
    return null;
  end if;
end;
$$ language plpgsql strict security definer;
comment on function app.authenticate(text, text) is
  'Creates a JWT token that will securely identify a person and give them certain permissions.';


-- function app.current_person
create function app.current_person() returns app.person as $$
  select *
  from app.person
  where id = current_setting('jwt.claims.person_id')::integer
$$ language sql stable;
comment on function app.current_person() is
  'Gets the person who was identified by our JWT.';



alter default privileges revoke execute on functions from public;

grant usage on schema app to app_anonymous, app_person;

grant select on table app.person to app_anonymous, app_person;
grant update, delete on table app.person to app_person;

grant select on table app.post to app_anonymous, app_person;
grant insert, update, delete on table app.post to app_person;
grant usage on sequence app.post_id_seq to app_person;

grant execute on function app.person_full_name(app.person) to app_anonymous, app_person;
grant execute on function app.post_summary(app.post, integer, text) to app_anonymous, app_person;
grant execute on function app.person_latest_post(app.person) to app_anonymous, app_person;
grant execute on function app.search_posts(text) to app_anonymous, app_person;
grant execute on function app.authenticate(text, text) to app_anonymous, app_person;
grant execute on function app.current_person() to app_anonymous, app_person;

grant execute on function app.register_person(text, text, text, text) to app_anonymous;


alter table app.person enable row level security;
alter table app.post enable row level security;


create policy select_person on app.person for select
  using (true);

create policy select_post on app.post for select
  using (true);

create policy update_person on app.person for update to app_person
  using (id = current_setting('jwt.claims.person_id')::integer);

create policy delete_person on app.person for delete to app_person
  using (id = current_setting('jwt.claims.person_id')::integer);

create policy insert_post on app.post for insert to app_person
  with check (author_id = current_setting('jwt.claims.person_id')::integer);

create policy update_post on app.post for update to app_person
  using (author_id = current_setting('jwt.claims.person_id')::integer);

create policy delete_post on app.post for delete to app_person
  using (author_id = current_setting('jwt.claims.person_id')::integer);




commit;
