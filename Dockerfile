FROM elixir:1.18-slim AS build

RUN apt-get update && \
    apt-get install -y --no-install-recommends build-essential git ca-certificates && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /app

ENV MIX_ENV=prod

RUN mix local.hex --force && \
    mix local.rebar --force

COPY mix.exs mix.lock ./
RUN mix deps.get --only prod

COPY config config
RUN mix deps.compile

COPY priv priv
COPY lib lib
COPY assets assets

RUN mix compile
RUN mix assets.deploy
RUN mix release

FROM debian:trixie-slim AS app

RUN apt-get update && \
    apt-get install -y --no-install-recommends libstdc++6 openssl ncurses-bin ca-certificates && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /app

ENV HOME=/app \
    LANG=C.UTF-8 \
    LC_ALL=C.UTF-8 \
    MIX_ENV=prod \
    PHX_SERVER=true \
    PORT=4000

COPY --from=build /app/_build/prod/rel/beacon_assistant ./
COPY knowledge-base ./knowledge-base

EXPOSE 4000

CMD ["/app/bin/beacon_assistant", "start"]
