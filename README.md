# Website Analyzer Tool

This tool analyzes a given URL to provide a report on load times, dead links, basic SEO metrics, and potential errors.

## Features

-   **Load Time:** Measures how long it takes for the main page to load.
-   **Dead Link Checker:** Scans the page for broken links (links returning 4xx or 5xx status codes).
-   **SEO Metrics:** Extracts basic SEO information:
    -   Page Title
    -   Meta Description
    -   Headings (H1-H6)
-   **Report Generation:** Produces an HTML report summarizing the findings.

## Prerequisites

-   Python 3.x
-   Required Python libraries:
    -   `requests`
    -   `BeautifulSoup4`
    -   `Jinja2`

## Setup

1.  **Clone the repository (or download the files).**
2.  **Navigate to the project directory.**
3.  **Install dependencies:**
    ```bash
    pip install requests beautifulsoup4 Jinja2
    ```
    (Note: The script attempts to install these if they are missing, but manual installation is recommended for clarity).

## Usage

Run the script from the command line, providing the URL you want to analyze.

```bash
python website_analyzer/main.py <URL_TO_ANALYZE> [options]
```

**Arguments:**

-   `<URL_TO_ANALYZE>`: (Required) The full URL of the website you want to analyze (e.g., `https://www.example.com`).
-   `-o OUTPUT_FILE`, `--output OUTPUT_FILE`: (Optional) The name of the HTML report file to generate. Defaults to `report.html` in the current working directory.

**Examples:**

1.  **Analyze a website and save the report as `report.html`:**
    ```bash
    python website_analyzer/main.py https://www.example.com
    ```

2.  **Analyze a website and save the report to a custom file named `my_client_report.html`:**
    ```bash
    python website_analyzer/main.py https://www.anotherwebsite.org -o my_client_report.html
    ```

## Interpreting the Report

The generated HTML report will contain the following sections:

-   **Analyzed URL:** The URL that was processed.
-   **Page Load Time:** Time taken for the initial page request to complete.
-   **HTTP Status Code:** The status code returned by the server for the main URL.
-   **SEO Metrics:**
    -   **Title:** The content of the page's `<title>` tag.
    -   **Meta Description:** The content of the `<meta name="description">` tag.
    -   **Headings:** A list of H1-H6 headings found on the page.
-   **Link Analysis:**
    -   Lists any dead or problematic links found on the page, along with their HTTP status code or the error encountered when trying to access them.
-   **JavaScript Errors:**
    -   Currently a placeholder. Full JavaScript error detection requires a headless browser (e.g., Selenium or Puppeteer) and is not implemented in this version.

## Future Enhancements

-   Full JavaScript console error capture.
-   More advanced SEO metrics (e.g., keyword density, image alt tags).
-   Screenshot of the page.
-   Integration with email services for automated report delivery.
-   Batch processing of multiple URLs.
