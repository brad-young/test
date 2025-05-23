require 'net/http'
require 'uri'
require 'nokogiri'

# Function to fetch content from URL
def fetch_flight_data(url_string)
  uri = URI.parse(url_string)
  http = Net::HTTP.new(uri.host, uri.port)
  http.use_ssl = (uri.scheme == 'https') # Enable SSL if URL is HTTPS

  request = Net::HTTP::Get.new(uri.request_uri)

  begin
    response = http.request(request)
    unless response.is_a?(Net::HTTPSuccess)
      raise "HTTP Error: #{response.code} #{response.message}"
    end
    return response.body
  rescue StandardError => e
    puts "Error fetching data: #{e.message}"
    return nil
  end
end

# Function to parse HTML content or pre-processed lines into flight data
def parse_flight_data(data_input, is_html_input: true)
  lines = []
  if is_html_input
    doc = Nokogiri::HTML(data_input)
    text_content = doc.at('body')&.text
    unless text_content
      puts "Warning: Could not extract text content from HTML body."
      return []
    end
    lines = text_content.lines.map(&:strip).reject(&:empty?)
  else # data_input is already an array of lines
    lines = data_input.map(&:strip).reject(&:empty?)
  end

  if lines.empty?
    puts "Warning: No text lines to process." if is_html_input # Only warn if it was supposed to be HTML
    return []
  end

  flights = []
  current_index = 0
  while current_index + 9 < lines.length
    chunk = lines[current_index, 10]
    destination = chunk[3]&.strip
    status = chunk[4]&.strip
    # Add validation similar to Python to skip non-plausible data (like headers)
    if destination && !destination.empty? && status && !status.empty? && destination.length > 2 && status.length > 1
      flights << { 'destination' => destination, 'status' => status }
    end
    current_index += 10
  end
  
  if current_index < lines.length && lines.length > 0
    puts "Warning: Skipping incomplete chunk at the end of data (lines #{current_index + 1}-#{lines.length}). Chunk size: #{lines.length - current_index}"
  end

  if flights.empty? && lines.length > 0
    puts "Warning: No flights extracted after processing #{lines.length} text lines in 10-line chunks."
  end
  
  flights
end

def filter_florida_flights_rb(parsed_flights)
  parsed_flights.select do |flight|
    flight['destination']&.end_with?(", FL")
  end
end

def aggregate_flight_data_rb(florida_flights)
  aggregated_data = Hash.new { |h, k| h[k] = Hash.new(0) }
  florida_flights.each do |flight|
    destination_city = flight['destination']
    flight_status = flight['status']
    aggregated_data[destination_city][flight_status] += 1
  end
  aggregated_data
end

def format_flight_summary_rb(aggregated_data)
  return nil if aggregated_data.nil? || aggregated_data.empty?
  
  output_lines = ["Florida Flight Status Summary:", "------------------------------"]
  aggregated_data.sort.to_h.each do |city, statuses|
    status_parts = []
    statuses.sort.to_h.each do |status, count|
      status_parts << "#{status} - #{count} flight#{count > 1 ? 's' : ''}"
    end
    output_lines << "#{city}: #{status_parts.join(', ')}"
  end
  output_lines << "------------------------------"
  output_lines.join("\n")
end

# Main processing logic callable from main or tests
def process_and_print_flights_rb(data_input, is_html_input: true)
  parsed_flights = parse_flight_data(data_input, is_html_input: is_html_input)

  if parsed_flights.nil? || parsed_flights.empty?
    puts "No flights parsed or an error occurred during parsing."
    return
  end

  florida_flights = filter_florida_flights_rb(parsed_flights)

  if florida_flights.empty?
    puts "No flights to Florida found."
    if parsed_flights.length > 0
       puts "Parsed #{parsed_flights.length} flights total, but none were for Florida."
    end
    return
  end

  aggregated_data = aggregate_flight_data_rb(florida_flights)
  
  output_string = format_flight_summary_rb(aggregated_data)
  if output_string
    puts output_string
  else
    puts "No data to display after filtering and aggregation."
  end
end

# Main script execution part
def main
  url = "https://tracker.flightview.com/FVAccess3/tools/fids/fidsDefault.asp?accCustId=PANYNJ&fidsId=20001&fidsInit=departures&fidsApt=EWR"
  html_content = fetch_flight_data(url)

  if html_content
    process_and_print_flights_rb(html_content, is_html_input: true)
  else
    puts "Failed to fetch flight data."
  end
end

# Run the main function if script is executed directly
if __FILE__ == $PROGRAM_NAME
  main
end
