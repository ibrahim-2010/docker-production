.PHONY: build run stop clean scan push logs

build:
	docker build -t flask-app:v2.0 .

run:
	docker compose up --build -d

stop:
	docker compose down

clean:
	docker compose down -v --rmi all

scan:
	trivy image --severity HIGH,CRITICAL flask-app:v2.0

push:
	docker tag flask-app:v2.0 ghcr.io/ibrahim-2010/docker-production:latest
	docker push ghcr.io/ibrahim-2010/docker-production:latest

logs:
	docker compose logs -f