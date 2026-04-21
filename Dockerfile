FROM golang:1.25-alpine AS builder
WORKDIR /src
COPY go.mod go.sum ./
RUN go mod download
COPY . .
RUN go build -o /desync ./cmd/desync

FROM alpine:3.21
RUN apk add --no-cache ca-certificates
COPY --from=builder /desync /usr/local/bin/desync
ENTRYPOINT ["desync"]
