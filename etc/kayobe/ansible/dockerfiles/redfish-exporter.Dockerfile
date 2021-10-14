FROM golang:alpine as builder
RUN apk add --no-cache git
RUN echo hi
RUN git clone https://github.com/jovial/redfish_exporter /build && cd /build && git checkout feature/log_counts
WORKDIR /build
RUN CGO_ENABLED=0 GOOS=linux go build -a -installsuffix cgo -ldflags '-extldflags "-static"' -o main .
FROM scratch
COPY --from=builder /build/main /app/
WORKDIR /app
CMD ["./main"]
