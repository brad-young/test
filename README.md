# SMS Scheduling Bot

This is a simple SMS bot that helps with scheduling groups of individuals by text messages.

## Features

- Tracks who's "in" and who's "out" for an event.
- Provides a summary of responses when prompted with `/summarize`.

## Setup

1. **Install dependencies:**
   ```bash
   pip install -r requirements.txt
   ```

2. **Run the application:**
   ```bash
   python app.py
   ```

3. **Configure Twilio:**
   - Create a Twilio account and get a Twilio phone number.
   - Set up a webhook for your Twilio number to point to the `/sms` endpoint of this application.

## Usage

- Send "in" or "me" to the Twilio number to mark yourself as "in".
- Send "out" to the Twilio number to mark yourself as "out".
- Send "/summarize" to the Twilio number to get a summary of responses.
