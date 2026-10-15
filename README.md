# mini-dfs

## Docker

Every component (name server, 4 chunk servers, client) runs in its own container.

```
mkdir -p files            # put files to upload here
docker compose up -d --build
docker compose run --rm client
(mini-dfs) write /files/hello.txt
(mini-dfs) lsf
(mini-dfs) read hello.txt 0 10
```

Configuration is passed through environment variables (see `globals.py`): `NAMESERVER_HOST`, `BIND_HOST`, `ADVERTISE_HOST`, `CHUNK_CLIENT_PORT`, `CLIENT_PORT`, `CHUNK_SERVER_PORT`.
The original single-process thread simulation is still available with `python src/mini_dfs/cli.py`.
