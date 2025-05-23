import requests
from bs4 import BeautifulSoup

def fetch_flight_data(url):
    """Fetches flight data from the given URL."""
    try:
        response = requests.get(url)
        response.raise_for_status()  # Raise an exception for bad status codes
        return response.text
    except requests.exceptions.RequestException as e:
        print(f"Error fetching data: {e}")
        return None

def parse_flight_data(flight_data_input, is_html_input=True):
    """
    Parses flight data from HTML (if is_html_input=True) or from a list of pre-processed text lines.
    """
    if is_html_input:
        soup = BeautifulSoup(flight_data_input, 'html.parser')
        text_content = soup.get_text(separator='\n', strip=True)
        lines = [line for line in text_content.split('\n') if line.strip()]
    else: # Assumes flight_data_input is already a list of clean text lines
        lines = flight_data_input # Already pre-processed

    if not lines:
        if is_html_input : print("Warning: No text lines extracted from HTML after stripping empty lines.")
        return []

    flights = []
    for i in range(0, len(lines), 10):
        chunk = lines[i:i+10]
        if len(chunk) == 10:
            destination = chunk[3].strip()
            status = chunk[4].strip()
            if destination and status and len(destination) > 2 and len(status) > 1:
                 flights.append({'destination': destination, 'status': status})
        else:
            if len(lines) - i < 10 and len(lines) - i > 0 :
                 print(f"Warning: Skipping incomplete chunk at the end of data (lines {i+1}-{i+len(chunk)}). Chunk size: {len(chunk)}")
    
    if not flights and lines: 
        # Avoid warning if input lines were empty to begin with for non-HTML case
        if is_html_input or any(lines): # Check if lines had content
            print(f"Warning: No flights extracted after processing {len(lines)} text lines in 10-line chunks.")
            if is_html_input:
                 print("This could be due to the HTML text structure not matching the 10-line assumption.")
    return flights

def filter_flights_by_state(parsed_flights, target_state): # Renamed and added target_state
    """Filters for flights heading to the specified state."""
    return [
        flight for flight in parsed_flights
        if flight['destination'].endswith(f", {target_state}") # Use target_state
    ]

def aggregate_flight_data(state_specific_flights): # Parameter name changed for clarity
    """Aggregates flight data by destination and status."""
    aggregated_data = {}
    for flight in state_specific_flights: # Use new parameter name
        destination = flight['destination']
        status = flight['status']
        if destination not in aggregated_data:
            aggregated_data[destination] = {}
        aggregated_data[destination][status] = aggregated_data[destination].get(status, 0) + 1
    return aggregated_data

def format_flight_summary(aggregated_data, target_state): # Added target_state
    """Formats the aggregated flight data into a printable string summary for the target state."""
    if not aggregated_data:
        return None
        
    output_lines = [f"{target_state} Flight Status Summary:", "------------------------------"] # Use target_state
    for city, statuses in sorted(aggregated_data.items()):
        status_parts = []
        for status, count in sorted(statuses.items()):
            status_parts.append(f"{status} - {count} flight{'s' if count > 1 else ''}")
        output_lines.append(f"{city}: {', '.join(status_parts)}")
    output_lines.append("------------------------------")
    return "\n".join(output_lines)

def process_and_print_flights(flight_data_html_or_text, target_state, is_html_input_flag=True): # Added target_state
    """
    Processes flight data (from HTML or pre-processed text) and prints the summary for the target_state.
    Set is_html_input_flag=False if flight_data_html_or_text is already processed text lines.
    """
    parsed_flights = parse_flight_data(flight_data_html_or_text, is_html_input=is_html_input_flag)

    if not parsed_flights:
        print("No flights parsed or an error occurred during parsing.")
        return

    state_specific_flights = filter_flights_by_state(parsed_flights, target_state) # Use renamed function

    if not state_specific_flights:
        print(f"No flights to {target_state} found.") # Use target_state in message
        if parsed_flights: 
            print(f"Found {len(parsed_flights)} flights total, but none were for {target_state}.")
        return

    aggregated_data = aggregate_flight_data(state_specific_flights) # Pass filtered flights
    
    output_string = format_flight_summary(aggregated_data, target_state) # Pass target_state
    if output_string:
        print(output_string)
    else:
        print("No data to display after filtering and aggregation.")

import argparse # Import argparse

def main():
    """Main function to orchestrate the flight data processing."""
    parser = argparse.ArgumentParser(description="Fetch and parse flight data for a specific state.")
    parser.add_argument(
        "--state", 
        type=str, 
        default="FL", 
        help="Target state abbreviation (e.g., FL, CA). Default is FL."
    )
    args = parser.parse_args()
    
    target_state = args.state.upper() # Convert to uppercase
    if not (len(target_state) == 2 and target_state.isalpha()):
        print(f"Warning: Invalid state abbreviation '{args.state}'. Must be 2 letters. Using default 'FL'.")
        target_state = "FL"
        
    print(f"Processing flights for state: {target_state}")

    url = "https://tracker.flightview.com/FVAccess3/tools/fids/fidsDefault.asp?accCustId=PANYNJ&fidsId=20001&fidsInit=departures&fidsApt=EWR"
    flight_data_html = fetch_flight_data(url)

    if flight_data_html:
        process_and_print_flights(flight_data_html, target_state, is_html_input_flag=True) # Pass target_state
    else:
        print("Failed to fetch flight data.")

if __name__ == "__main__":
    main()
