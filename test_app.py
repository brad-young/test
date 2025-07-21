import unittest
import xml.etree.ElementTree as ET
from app import app

class SMSTestCase(unittest.TestCase):

    def setUp(self):
        self.app = app.test_client()
        self.app.testing = True
        app.config['TESTING'] = True


    def test_sms_reply_in(self):
        response = self.app.post('/sms', data=dict(Body='in', From='+1234567890'))
        self.assertEqual(response.status_code, 200)
        root = ET.fromstring(response.data)
        self.assertEqual(root.find('Message').text, "You're in!")

    def test_sms_reply_out(self):
        response = self.app.post('/sms', data=dict(Body='out', From='+1234567890'))
        self.assertEqual(response.status_code, 200)
        root = ET.fromstring(response.data)
        self.assertEqual(root.find('Message').text, "You're out.")

    def test_sms_reply_summarize(self):
        with self.app as c:
            c.post('/sms', data=dict(Body='in', From='+1234567890'))
            c.post('/sms', data=dict(Body='out', From='+10987654321'))
            response = c.post('/sms', data=dict(Body='/summarize', From='+1234567890'))
            self.assertEqual(response.status_code, 200)
            root = ET.fromstring(response.data)
            self.assertIn('+1234567890: in', root.find('Message').text)
            self.assertIn('+10987654321: out', root.find('Message').text)


if __name__ == '__main__':
    unittest.main()
