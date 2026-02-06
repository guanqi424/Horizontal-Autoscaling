# --- build cpu-burner ---
FROM golang:1.22-alpine AS builder
WORKDIR /src
COPY cpu-burner.go .
RUN go build -o cpu-burner cpu-burner.go
COPY cpu-work.go .
RUN go build -o cpu-work cpu-work.go


# --- final image: nginx + cpu-burner ---
FROM nginx:alpine
WORKDIR /app

COPY --from=builder /src/cpu-burner /app/cpu-burner
COPY --from=builder /src/cpu-work /app/cpu-work
COPY start.sh /app/start.sh
COPY index.html /usr/share/nginx/html/index.html

RUN chmod +x /app/start.sh /app/cpu-burner /app/cpu-work

EXPOSE 80 8081 8082
CMD ["/app/start.sh"]
