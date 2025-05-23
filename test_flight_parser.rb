require 'minitest/autorun'
# Adjust the path if flight_parser.rb is not in the same directory or not in $LOAD_PATH
require_relative 'flight_parser'

# Sample data as specified in the problem description
SAMPLE_FLIGHT_DATA_TEXT_RB = <<~TEXT
Airline
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
TEXT

class TestFlightParserRb < Minitest::Test
  def setup
    @sample_lines = SAMPLE_FLIGHT_DATA_TEXT_RB.lines.map(&:strip).reject(&:empty?)
    # Process the sample data once for all tests
    @parsed_flights = parse_flight_data(@sample_lines, is_html_input: false)
    @florida_flights = filter_florida_flights_rb(@parsed_flights)
    @aggregated_data = aggregate_flight_data_rb(@florida_flights)
  end

  def test_parse_data
    # Based on the Python test, the sample data produces 9 "flights"
    # The first chunk from sample data is:
    # Airline, Flight, Flight, To, Status, Sched., Update, Status, Term-Gate, Status
    # This will be parsed as {'destination' => 'To', 'status' => 'Status'} by current parser.
    # This is consistent with Python test observation.
    # Total 90 lines -> 9 chunks.
    assert_equal 9, @parsed_flights.length
    assert_includes @parsed_flights, { 'destination' => 'Orlando, FL', 'status' => 'In Air' }
    assert_includes @parsed_flights, { 'destination' => 'NonFlorida, XY', 'status' => 'Scheduled' }
    # Check first parsed item
    assert_equal ({ 'destination' => 'Orlando, FL', 'status' => 'In Air' }), @parsed_flights[0]
  end

  def test_filter_florida_flights
    # Expected Florida flights: Orlando (3), Key West (1), Tampa (2), Miami (1) = 7
    assert_equal 7, @florida_flights.length
    
    destinations = @florida_flights.map { |flight| flight['destination'] }
    refute_includes destinations, "Montreal"
    refute_includes destinations, "NonFlorida, XY"
  end

  def test_aggregate_flight_data
    expected_aggregation = {
      "Orlando, FL" => {"In Air" => 1, "Departed" => 2},
      "Key West, FL" => {"Departed" => 1},
      "Tampa, FL" => {"Departed" => 1, "Delayed" => 1},
      "Miami, FL" => {"Departed" => 1}
    }
    assert_equal expected_aggregation, @aggregated_data
  end

  def test_format_flight_summary
    formatted_output = format_flight_summary_rb(@aggregated_data)
    
    expected_output_lines = [
      "Florida Flight Status Summary:",
      "------------------------------",
      "Key West, FL: Departed - 1 flight",
      "Miami, FL: Departed - 1 flight",
      "Orlando, FL: Departed - 2 flights, In Air - 1 flight", # Sorted by status: Departed, In Air
      "Tampa, FL: Delayed - 1 flight, Departed - 1 flight",   # Sorted by status: Delayed, Departed
      "------------------------------"
    ]
    assert_equal expected_output_lines.join("\n"), formatted_output
  end

  def test_empty_data_handling
    empty_parsed = []
    filtered_empty = filter_florida_flights_rb(empty_parsed)
    assert_equal [], filtered_empty
    aggregated_empty = aggregate_flight_data_rb(filtered_empty)
    assert_equal({}, aggregated_empty)
    formatted_empty = format_flight_summary_rb(aggregated_empty)
    assert_nil formatted_empty # Expecting nil for empty data
  end

  def test_no_florida_flights
    non_fl_data = [
      { 'destination' => 'Montreal, QC', 'status' => 'Scheduled' },
      { 'destination' => 'Toronto, ON', 'status' => 'Delayed' }
    ]
    filtered = filter_florida_flights_rb(non_fl_data)
    assert_equal [], filtered
    aggregated = aggregate_flight_data_rb(filtered)
    assert_equal({}, aggregated)
    formatted = format_flight_summary_rb(aggregated)
    assert_nil formatted
  end
end
