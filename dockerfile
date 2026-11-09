FROM alpine:3.20
RUN apk add --no-cache bash gawk coreutils
WORKDIR /app
COPY process-sales.sh .
RUN chmod +x process-sales.sh
CMD ["sh", "-c", "while true; do ./process-sales.sh; sleep 10; done"]