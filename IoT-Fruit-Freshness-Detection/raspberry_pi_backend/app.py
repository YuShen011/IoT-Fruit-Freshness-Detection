from flask import Flask, jsonify, Response
import cv2
import time
import adafruit_dht
import board
import RPi.GPIO as GPIO
import os
from threading import Thread, Lock
import atexit
from ultralytics import YOLO
import gspread
from oauth2client.service_account import ServiceAccountCredentials
from datetime import datetime

app = Flask(__name__)

# Initialize DHT22 sensor
dht_device = adafruit_dht.DHT22(board.D4)

# Initialize YOLO model
yolo_model = YOLO("/home/pi/capstone/best.pt")

# Global variables for sensor data and fruit status
sensor_data = {
    "temperature_c": None,
    "temperature_f": None,
    "humidity": None,
    "alcohol": None,
    "fruit_status": None
}
current_frame = None

start_time = time.time()
elapsed_time = 0
previous_fruit_status = "empty"
lock = Lock()

# Function to continuously read from the MQ3 sensor
def update_alcohol_data():
    global sensor_data
    while True:
        input_state = GPIO.input(8)
        if input_state == 0:
            alcohol_status = "Detected"
            print("MQ3: Alcohol is detected")
            sensor_data.update({"alcohol": alcohol_status})
        else:
            alcohol_status = "Not detected"
            print("MQ3: {}".format(alcohol_status))
            sensor_data.update({"alcohol": alcohol_status})
        time.sleep(2.0)

# Function to continuously read from the DHT22 sensor
def update_sensor_data():
    global sensor_data
    while True:
        try:
            temperature_c = dht_device.temperature
            temperature_f = temperature_c * (9 / 5) + 32
            humidity = dht_device.humidity
            
            print("Temp: {:.1f} C / {:.1f} F   Humidity: {}%".format(temperature_c, temperature_f, humidity))

            sensor_data.update({
                "temperature_c": round(temperature_c, 2),
                "temperature_f": round(temperature_f, 2),
                "humidity": round(humidity, 2),
            })
        except RuntimeError as err:
            print(f"DHT22 Error: {err.args[0]}")
        time.sleep(5.0)

#Funtion to capture frames
def capture_frames():
    global current_frame
    camera = cv2.VideoCapture(0)
    if not camera.isOpened():
        print("Error: Cannot open camera index 0")
        return

    while True:
        success, frame = camera.read()
        if success:
            current_frame = frame
        else:
            print("Error: Failed to capture image")
        time.sleep(0.1)

    camera.release()

#Function to generate frames
def generate_frames():
    global current_frame
    while True:
        if current_frame is not None:
            ret, buffer = cv2.imencode('.jpg', current_frame)
            frame = buffer.tobytes()
            yield (b'--frame\r\n'
                   b'Content-Type: image/jpeg\r\n\r\n' + frame + b'\r\n')

# Function to continuously analyze fruit status using YOLO
def update_fruit_status():
    global sensor_data, current_frame, start_time, elapsed_time, previous_fruit_status
    while True:
        if current_frame is not None:
            results = yolo_model(current_frame)
            detections = results[0].boxes.data  # Access YOLO detections directly
            
            if len(detections) > 0:
                class_name = "empty"
                for detection in detections:
                    class_id = int(detection[5])
                    if yolo_model.names[class_id] == "rotten_apple":
                        class_name = "rotten_apple"
                        break
                    elif yolo_model.names[class_id] == "fresh_apple":
                        class_name = "fresh_apple"
            else:
                class_name = "empty"
            
            with lock:
                # Reset the timer if the fruit status changes between 'empty' and 'fresh_apple'/'rotten_apple'
                if (previous_fruit_status == "empty" and class_name in ["fresh_apple", "rotten_apple"]) or \
                   (previous_fruit_status in ["fresh_apple", "rotten_apple"] and class_name == "empty"):
                    start_time = time.time()  # Reset the start time
                    elapsed_time = 0  # Reset the elapsed time
                
                # Update the elapsed time for both 'empty' and 'fresh_apple'/'rotten_apple'
                elapsed_time = time.time() - start_time
                
                # Update the fruit status
                sensor_data.update({"fruit_status": class_name})
                previous_fruit_status = class_name
        else:
            print("Current frame is none.")
        
        time.sleep(2.0)

# Google Sheets API setup
def setup_google_sheets():
    scope = ["https://spreadsheets.google.com/feeds", "https://www.googleapis.com/auth/drive"]
    creds = ServiceAccountCredentials.from_json_keyfile_name("YOUR_GOOGLE_SHEETS_CREDENTIAL_PATH", scope)
    client = gspread.authorize(creds)
    sheet = client.open("Capstone Time Log").sheet1
    return sheet
    
# Log status change to Google Sheet
def log_status_change(condition):
    sheet = setup_google_sheets()
    now = datetime.now()
    date = now.strftime("%Y-%m-%d")
    time = now.strftime("%H:%M:%S")
    sheet.append_row([date, time, condition])

# Monitor the rack status
def monitor_rack_status():
    global sensor_data
    
    monitor_previous_fruit_status = sensor_data.get("fruit_status", "empty")
    
    while True:
        current_fruit_status = sensor_data.get("fruit_status", "empty")
        
        # Use pattern matching to handle transitions
        match (monitor_previous_fruit_status, current_fruit_status):
            case ("empty", "fresh_apple") | ("empty", "rotten_apple"):
                log_status_change("replenished")
            case ("fresh_apple", "empty") | ("rotten_apple", "empty"):
                log_status_change("sold out")
            case _:
                pass
        
        monitor_previous_fruit_status = current_fruit_status
        
        time.sleep(2.0)

# Initialize MQ3 sensor
try:
    GPIO.setwarnings(False)  # Suppress GPIO warnings
    GPIO.setmode(GPIO.BCM)
    GPIO.setup(8, GPIO.IN)
    time.sleep(0.1) #Small delay to ensure setup is complete.
    print("GPIO setup completed successfully")   # Debug statement
except ValueError as e:
    print(f"GPIO setup error: {e}")

# Start frame capture thread
frame_capture_thread = Thread(target=capture_frames)
frame_capture_thread.daemon = True
frame_capture_thread.start()

# Start the sensor update threads
sensor_thread = Thread(target=update_sensor_data)
sensor_thread.daemon = True
sensor_thread.start()

# Start the alcohol update threads
alcohol_thread = Thread(target=update_alcohol_data)
alcohol_thread.daemon = True
alcohol_thread.start()

# Start the yolo update threads
yolo_thread = Thread(target=update_fruit_status)
yolo_thread.daemon = True
yolo_thread.start()

# Start the monitoring thread
monitor_thread = Thread(target=monitor_rack_status)
monitor_thread.daemon = True
monitor_thread.start()

# Route to root path
@app.route('/', methods=['GET'])
def home():
    return "Welcome to the Home Page!"

# Route to fetch elapsed time
@app.route('/elapsed_time', methods=['GET'])
def elapsed_time_route():
    with lock:
        return jsonify({"elapsed_time": elapsed_time})

# Route to fetch sensor data
@app.route('/sensor_data', methods=['GET'])
def sensor_data_route():
    return jsonify(sensor_data)

# Route to fetch video feed
@app.route('/video_feed', methods=['GET'])
def video_feed():
    return Response(generate_frames(), mimetype='multipart/x-mixed-replace; boundary=frame')

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000)
