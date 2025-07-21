from flask import Flask, request, jsonify
from twilio.twiml.messaging_response import MessagingResponse

app = Flask(__name__)

@app.route("/", methods=["GET"])
def index():
    return "Hello, World!"

responses = {}

@app.route("/sms", methods=['POST'])
def sms_reply():
    """Respond to incoming calls with a simple text message."""
    # Fetch the message
    msg = request.form.get('Body').lower()
    from_number = request.form.get('From')

    # Create reply
    resp = MessagingResponse()

    if msg == '/summarize':
        summary = "Summary of responses:\n"
        for number, status in responses.items():
            summary += f"{number}: {status}\n"
        resp.message(summary)
    elif 'in' in msg or 'me' in msg:
        responses[from_number] = 'in'
        resp.message("You're in!")
    elif 'out' in msg:
        responses[from_number] = 'out'
        resp.message("You're out.")
    else:
        resp.message("I didn't understand your response. Please say 'in' or 'out'.")

    return str(resp)

if __name__ == "__main__":
    app.run(debug=True)
