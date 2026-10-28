# Build em Debian; execução em distroless sem shell, não-root, binário estático.
# Nenhuma toolchain na máquina do desenvolvedor (ambiente-local.mdc).

FROM golang:1.25-bookworm AS build
WORKDIR /src
ENV CGO_ENABLED=0 GOFLAGS=-mod=readonly
COPY go.mod go.sum ./
RUN go mod download
COPY cmd ./cmd
COPY internal ./internal
RUN go build -trimpath -ldflags="-s -w" -o /out/web ./cmd/web \
 && go build -trimpath -ldflags="-s -w" -o /out/worker ./cmd/worker

FROM gcr.io/distroless/static-debian12:nonroot AS web
COPY --from=build /out/web /web
USER nonroot:nonroot
EXPOSE 8080
ENTRYPOINT ["/web"]

FROM gcr.io/distroless/static-debian12:nonroot AS worker
COPY --from=build /out/worker /worker
USER nonroot:nonroot
ENTRYPOINT ["/worker"]
