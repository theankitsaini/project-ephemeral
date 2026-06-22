from fastapi import FastAPI
import random

app = FastAPI()

BIKE_STATIONS = ["Amsterdam Centraal", "Dam Square", "Rijksmuseum", "Vondelpark", "Jordaan"]

@app.get("/")
def read_root():
    return {"status": "healthy", "message": "Welkom bij de Amsterdam Bike Share API!"}

@app.get("/bikes")
def get_bikes():
    return {
        "station": random.choice(BIKE_STATIONS),
        "available_bikes": random.randint(0, 25),
        "available_docks": random.randint(0, 30)
    }

@app.get("/metrics")
def metrics():
    # Mock metrics format for Prometheus scraping
    return "# HELP bike_api_uptime Uptime indicator\n# TYPE bike_api_uptime gauge\nbike_api_uptime 1\n"