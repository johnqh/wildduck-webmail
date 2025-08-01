## Development

Ensure you have [Node.js](https://nodejs.org/en/) installed.
Ensure you have [Docker](https://www.docker.com/) installed.

- Install dependencies

```
npm install
```

- Install bower dependencies

```
npm run bowerdeps
```

- Setup Redis

Use docker to setup redis

```
docker run --name my-redis-container -d -p 6379:6379 redis/redis-stack-server:latest
```

- Update config

Update ./config/default.toml

[service]
domain="your domain" # your domain
domains=["your domain"] # your domain
[api]
url="https://wildduck.com" # your wildduck server url
accessToken="your access token" # your wildduck access token

[setup]
[setup.imap]
hostname="wildduck.com" # your wildduck server hostname
port=993 # imap port
...

- Run server

```
npm start

```
