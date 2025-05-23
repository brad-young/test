import unittest
from flight_parser import parse_flight_data, filter_florida_flights, aggregate_flight_data, format_flight_summary

# Sample data as specified in the problem description
SAMPLE_FLIGHT_DATA_TEXT = """Airline
Flight
Flight
To
Status
Sched.
Update
Status
Term-Gate
Status
NK Spirit Airlines
2554
NK2554
Orlando, FL
In Air
6:45 AM
9:46 AM
In Air
Term. B - B48
In Air
UA United Airlines
1822
UA1822
Key West, FL
Departed
9:37 AM
9:57 AM
Departed
Term. A - A17
Departed
AC Air Canada
8939
AC8939
Montreal
Delayed
7:45 AM
10:40 AM
Delayed
Term. A - A1
Delayed
LY El Al Israel Airlines
8766
LY8766
Orlando, FL
Departed
9:55 AM
10:06 AM
Departed
Term. A - A31
Departed
B6 Jetblue Airways Corporation
127
B6127
Orlando, FL
Departed
9:55 AM
10:06 AM
Departed
Term. A - A31
Departed
AC Air Canada
3230
AC3230
Tampa, FL
Departed
10:00 AM
10:10 AM
Departed
Term. C - C120
Departed
UA United Airlines
548
UA548
Tampa, FL
Delayed
10:00 AM
10:10 AM
Delayed
Term. C - C120
Delayed
AC Air Canada
3163
AC3163
Miami, FL
Departed
10:02 AM
9:59 AM
Departed
Term. C - C81
Departed
UA United Airlines
2499
UA2499
NonFlorida, XY
Scheduled
10:02 AM
9:59 AM
Scheduled
Term. C - C81
Scheduled
"""

class TestFlightParser(unittest.TestCase):

    @classmethod
    def setUpClass(cls):
        # Convert the multiline string to a list of lines, similar to how it would be after initial text extraction
        cls.sample_lines = [line for line in SAMPLE_FLIGHT_DATA_TEXT.strip().split('\n') if line.strip()]
        # Process the sample data once for all tests
        cls.parsed_flights = parse_flight_data(cls.sample_lines, is_html_input=False)
        cls.florida_flights = filter_florida_flights(cls.parsed_flights)
        cls.aggregated_data = aggregate_flight_data(cls.florida_flights)

    def test_parse_data(self):
        # Check number of flights parsed (9 total entries, 10 lines each, minus the header 10 lines)
        # The sample data has a 10-line header, then 9 flight entries.
        # Each flight entry provides 'To' (destination) and 'Status'.
        # Total lines = 10 (header) + 9 * 10 (flights) = 100 lines.
        # parse_flight_data processes in 10-line chunks.
        # The first chunk is header, lines 3 and 4 are "To" and "Status", which are valid strings.
        # So it will parse it as a flight. This is a known behavior of the current parser.
        # If the problem implies the first 10 lines are a header to be ignored, the parser would need adjustment.
        # Given the current parser, it will find 9 "flights".
        # Let's re-verify the sample data structure:
        # Header (10 lines)
        # Flight 1 (10 lines) - Orlando, FL / In Air
        # Flight 2 (10 lines) - Key West, FL / Departed
        # Flight 3 (10 lines) - Montreal / Delayed  (Non-FL)
        # Flight 4 (10 lines) - Orlando, FL / Departed
        # Flight 5 (10 lines) - Orlando, FL / Departed
        # Flight 6 (10 lines) - Tampa, FL / Departed
        # Flight 7 (10 lines) - Tampa, FL / Delayed
        # Flight 8 (10 lines) - Miami, FL / Departed
        # Flight 9 (10 lines) - NonFlorida, XY / Scheduled (Non-FL)
        # The first chunk (header) will be parsed as: destination="To", status="Status"
        # This is how the current parser works. If this is not desired, the parser or test data needs change.
        # For now, I'll assume this behavior is within the test scope.
        # So, 9 actual flights + 1 "header flight" = 10.
        
        # Correcting the expectation: The problem says "this is a simplified text representation,
        # assuming the HTML parsing part ... correctly extracts this kind of text line sequence".
        # The sample data starts with "Airline", "Flight", "Flight", "To", "Status", ...
        # This is the *first* 10-line chunk.
        # So, the parser will extract {'destination': 'To', 'status': 'Status'} as the first item.
        # Then 8 actual flights. Total 9.
        # The prompt sample has 90 lines of data, which forms 9 chunks.
        self.assertEqual(len(self.parsed_flights), 9)
        self.assertIn({'destination': 'Orlando, FL', 'status': 'In Air'}, self.parsed_flights)
        self.assertIn({'destination': 'NonFlorida, XY', 'status': 'Scheduled'}, self.parsed_flights)
        # The first item from the sample will be:
        self.assertEqual(self.parsed_flights[0], {'destination': 'Orlando, FL', 'status': 'In Air'})


    def test_filter_florida_flights(self):
        # Expected Florida flights: Orlando (3), Key West (1), Tampa (2), Miami (1) = 7
        self.assertEqual(len(self.florida_flights), 7)
        # Check that a non-Florida flight is excluded
        destinations = [flight['destination'] for flight in self.florida_flights]
        self.assertNotIn("Montreal", destinations)
        self.assertNotIn("NonFlorida, XY", destinations)

    def test_aggregate_flight_data(self):
        expected_aggregation = {
            "Orlando, FL": {"In Air": 1, "Departed": 2},
            "Key West, FL": {"Departed": 1},
            "Tampa, FL": {"Departed": 1, "Delayed": 1},
            "Miami, FL": {"Departed": 1}
        }
        self.assertEqual(self.aggregated_data, expected_aggregation)

    def test_format_flight_summary(self):
        # Test formatting for a specific city to check structure
        # For this, we'd need to format just a part or check the whole string
        formatted_output = format_flight_summary(self.aggregated_data)
        
        expected_output_lines = [
            "Florida Flight Status Summary:",
            "------------------------------",
            "Key West, FL: Departed - 1 flight",
            "Miami, FL: Departed - 1 flight",
            "Orlando, FL: Departed - 2 flights, In Air - 1 flight", # Note: Departed comes before In Air due to sort
            "Tampa, FL: Delayed - 1 flight, Departed - 1 flight", # Note: Delayed comes before Departed
            "------------------------------"
        ]
        # Order of statuses within a city depends on sorted(statuses.items()).
        # 'Departed' comes before 'In Air'.
        # 'Delayed' comes before 'Departed'.
        
        # Let's re-verify sorted order of statuses for Orlando:
        # Orlando, FL: In Air - 1, Departed - 2. Sorted: Departed, In Air.
        # Correct: "Orlando, FL: Departed - 2 flights, In Air - 1 flight"

        # For Tampa: Departed - 1, Delayed - 1. Sorted: Delayed, Departed
        # Correct: "Tampa, FL: Delayed - 1 flight, Departed - 1 flight"
        
        self.assertEqual(formatted_output, "\n".join(expected_output_lines))

    def test_empty_data_handling(self):
        empty_parsed = []
        filtered_empty = filter_florida_flights(empty_parsed)
        self.assertEqual(filtered_empty, [])
        aggregated_empty = aggregate_flight_data(filtered_empty)
        self.assertEqual(aggregated_empty, {})
        formatted_empty = format_flight_summary(aggregated_empty)
        self.assertIsNone(formatted_empty) # Expecting None or an empty string based on implementation

    def test_no_florida_flights(self):
        non_fl_data = [
            {'destination': 'Montreal, QC', 'status': 'Scheduled'},
            {'destination': 'Toronto, ON', 'status': 'Delayed'}
        ]
        filtered = filter_florida_flights(non_fl_data)
        self.assertEqual(filtered, [])
        aggregated = aggregate_flight_data(filtered)
        self.assertEqual(aggregated, {})
        formatted = format_flight_summary(aggregated)
        self.assertIsNone(formatted)

if __name__ == '__main__':
    unittest.main()
