FROM clux/muslrust:stable AS chef
WORKDIR /app
RUN cargo install cargo-chef


FROM chef AS planner
WORKDIR /app
COPY . .
RUN cargo chef prepare --recipe-path recipe.json


FROM chef as development
WORKDIR /app
ARG UID=1000
ARG RUN_AS_USER=appuser
ARG IDX_BACK_API_PORT=3001
# Add the app user for development
ENV USER=appuser
ENV UID=$UID
RUN adduser --uid "${UID}" "${USER}"
# Build dependencies
COPY --from=planner /app/recipe.json recipe.json
RUN cargo chef cook --recipe-path recipe.json
# Build the application
COPY . .
RUN cargo build --bin main
USER $RUN_AS_USER:$RUN_AS_USER
EXPOSE $IDX_BACK_API_PORT/tcp  
CMD ["cargo", "run"]


FROM chef AS builder
WORKDIR /app
ARG UID=1000
# Add the app user for production
ENV USER=appuser
ENV UID=$UID
RUN adduser \
  --disabled-password \
  --gecos "" \
  --home "/nonexistent" \
  --shell "/sbin/nologin" \
  --no-create-home \
  --uid "${UID}" \
  "${USER}"  
# Build dependencies
COPY --from=planner /app/recipe.json recipe.json
RUN cargo chef cook --release --target x86_64-unknown-linux-musl --recipe-path recipe.json
# Build the application
COPY . .
RUN cargo build --release --target x86_64-unknown-linux-musl --bin main
# Strip the binary
# More info: https://github.com/LukeMathWalker/cargo-chef/issues/149
RUN strip /app/target/x86_64-unknown-linux-musl/release/main


FROM alpine:latest
WORKDIR /app
ARG RUN_AS_USER=appuser
ARG IDX_BACK_API_PORT=3001
RUN apk --no-cache add ca-certificates
ENV TZ=Etc/UTC
ENV RUN_AS_USER=$RUN_AS_USER
COPY --from=builder /etc/passwd /etc/passwd
COPY --from=builder /etc/group /etc/group
COPY --from=builder --chown=$RUN_AS_USER \
  /app/target/x86_64-unknown-linux-musl/release/main \
  /app/main
RUN chown -R $RUN_AS_USER:$RUN_AS_USER /app
USER $RUN_AS_USER:$RUN_AS_USER
EXPOSE $IDX_BACK_API_PORT/tcp
ENTRYPOINT ["/app/main"]