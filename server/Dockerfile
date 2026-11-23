FROM golang:1.24-alpine AS builder
WORKDIR /app
COPY go.mod ./
COPY *.go ./
RUN go mod tidy && CGO_ENABLED=0 GOOS=linux go build -ldflags="-s -w" -o /out/wwp-server .

FROM alpine:3.21
RUN apk add --no-cache ca-certificates wget && adduser -D -u 10001 wwp
WORKDIR /app
COPY --from=builder /out/wwp-server /app/wwp-server
USER wwp
EXPOSE 8080
HEALTHCHECK --interval=15s --timeout=4s --start-period=5s --retries=3 CMD wget -qO- http://127.0.0.1:8080/health || exit 1
ENTRYPOINT ["/app/wwp-server"]
