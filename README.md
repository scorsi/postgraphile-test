# postgraphile-example
This is a short postgraphile API example

Run with `./start.sh` and stop with `./stop.sh`.

Needs postgresql or psql tool installed and postgraphile installed (`npm install -g postgraphile`).

After running the start script, open your browser and go to `localhost:5000/graphiql`.

You can know play with your PostgreSQL backend application served with GraphQL.

To connect yourself:
```graphql
mutation {
  authenticate(input: {email: "spowell0@noaa.gov", password: "iFbWWlc"}) {
    jwtToken
  }
}
```

To get 10 recent posts:
```graphql
query {
  allPosts(first: 10, orderBy: CREATED_AT_DESC) {
    nodes {
     	authorId
      headline
      topic
      createdAt
    }
  }
}
```

To register an account:
```graphql
mutation {
  registerPerson(input: {firstName: "Sylvain", lastName: "Corsini", email:"sylvain.corsini@protonmail.com", password:"secret"}) {
    person {
      id
    }
  }
}
```


To get the current logged account (should not work if you're not registered to an account):
```graphql
query {
  currentPerson {
    id
  }
}
```
But if you authenticate before and execute the request with curl and adding the authorization header, it should work:
```
curl -H "Authorization: Bearer YOURTOKEN" -X POST -d " \
 { \
   \"query\": \"query { currentPerson { id } }\" \
 } \
" localhost:5000/graphql
```
Which will returns you:
```json
{
  "data": {
    "currentPerson": {
      "id": 11
    }
  }
}
```

You can delete your freshly created account:
```graphql
mutation {
  deletePersonById(input: {id: 11}) {
    deletedPersonId
  }
}
```

And if you try again to run the currentPerson query, you will get:
```json
{
  "data": {
    "currentPerson": null
  }
}
```
