# IoT-Based Automated Fruit Freshness Detection

## 📌 Project Overview
This project introduces a smart IoT system designed to monitor and evaluate fruit freshness in supermarket environments. By combining environmental monitoring and computer vision, the system aims to automate freshness tracking, reduce manual labor, and minimize food waste.

## ⚙️ Hardware Stack
* **Microcontroller:** Raspberry Pi 4 Model B
* **Sensors:** DHT22 (Temperature & Humidity), MQ3 (Gas/Alcohol for ethylene detection)
* **Camera:** Logitech USB Camera
* **Circuitry:** Strip Board and ADS1115 ADC

## 💻 Software Stack
* **Backend:** Python, Flask (API development), OpenCV (Image processing)
* **Computer Vision:** YOLOv11 for real-time object detection (trained via Google Colab)
* **Frontend UI:** Flutter/Dart mobile application
* **Database/Logging:** Google Sheets API

## 🚀 Key Features
* **Real-Time Image Processing:** Detects if fruits are "fresh," "rotten," or if the rack is "empty" using YOLOv11.
* **Environmental Monitoring:** Tracks real-time temperature, humidity, and alcohol levels.
* **Mobile Dashboard:** A Flutter app that provides a live video feed, sensor readings, time logs, and QR code scanning for rack identification.
* **Alert System:** Triggers push notifications to staff when spoilage is detected or environmental conditions become abnormal.

## 📁 Repository Structure
* `/model_training`: Google Colab scripts for training and testing the YOLOv11 model.
* `/raspberry_pi_backend`: Python Flask server handling sensor data collection, OpenCV framing, YOLO inference, and Google Sheets logging.
* `/flutter_app`: Dart source code for the mobile Human-Machine Interface (HMI).