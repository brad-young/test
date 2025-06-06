import requests
import time
from bs4 import BeautifulSoup
from urllib.parse import urljoin
from jinja2 import Environment, FileSystemLoader, select_autoescape, TemplateNotFound
import argparse

def extract_seo_metrics(html_content):
    """
    Extracts SEO-related metrics from HTML content.

    Args:
        html_content (str): The HTML content of the page.

    Returns:
        dict: A dictionary containing SEO metrics (title, meta_description, headings).
    """
    if not html_content:
        return {
            'title': None,
            'meta_description': None,
            'headings': []
        }

    soup = BeautifulSoup(html_content, 'html.parser')
    seo_metrics = {}

    # Title Tag
    title_tag = soup.find('title')
    seo_metrics['title'] = title_tag.get_text(strip=True) if title_tag else None

    # Meta Description
    meta_desc_tag = soup.find('meta', attrs={'name': 'description'})
    seo_metrics['meta_description'] = meta_desc_tag['content'].strip() if meta_desc_tag and 'content' in meta_desc_tag.attrs else None

    # Headings
    seo_metrics['headings'] = []
    for i in range(1, 7):
        for tag in soup.find_all(f'h{i}'):
            seo_metrics['headings'].append({'tag': tag.name, 'text': tag.get_text(strip=True)})

    return seo_metrics

def check_dead_links(base_url, html_content):
    """
    Checks for dead links (status >= 400) on a given HTML page.

    Args:
        base_url (str): The base URL of the page, used for resolving relative links.
        html_content (str): The HTML content of the page.

    Returns:
        list: A list of dictionaries, each representing a dead link
              with 'url', 'status_code', and optionally 'error'.
    """
    if not html_content:
        return []

    soup = BeautifulSoup(html_content, 'html.parser')
    dead_links = []

    for a_tag in soup.find_all('a', href=True):
        href = a_tag['href']
        absolute_url = urljoin(base_url, href)

        if not absolute_url.startswith(('http://', 'https://')):
            continue

        try:
            response = requests.head(absolute_url, timeout=5, allow_redirects=True)
            if response.status_code >= 400:
                dead_links.append({'url': absolute_url, 'status_code': response.status_code})
        except requests.exceptions.RequestException as e:
            dead_links.append({'url': absolute_url, 'status_code': None, 'error': str(e)})

    return dead_links

def analyze_url(url):
    """
    Analyzes a given URL, fetches its content, measures load time,
    checks for dead links, and extracts SEO metrics.

    Args:
        url (str): The URL to analyze.

    Returns:
        dict: A dictionary containing analysis results or error information.
    """
    try:
        start_time = time.time()
        response = requests.get(url, timeout=10)
        response.raise_for_status() # Raise HTTPError for bad responses (4xx or 5xx)
        end_time = time.time()
        load_time = end_time - start_time
        html_content = response.text

        dead_links_list = check_dead_links(url, html_content)
        seo_metrics_data = extract_seo_metrics(html_content)

        return {
            'url': url,
            'status_code': response.status_code,
            'load_time': load_time,
            'html_content': html_content,
            'dead_links': dead_links_list,
            'seo_metrics': seo_metrics_data,
            'javascript_errors': []  # Placeholder for JavaScript console errors
        }
    except requests.exceptions.HTTPError as e: # More specific error for HTTP errors
        return {
            'url': url,
            'error': f"HTTP error fetching URL: {e}",
            'status_code': e.response.status_code if e.response else None,
            'load_time': None,
            'html_content': None,
            'dead_links': [],
            'seo_metrics': { 'title': None, 'meta_description': None, 'headings': [] },
            'javascript_errors': []
        }
    except requests.exceptions.RequestException as e: # General request error
        return {
            'url': url,
            'error': f"Error fetching URL: {e}",
            'status_code': None,
            'load_time': None,
            'html_content': None,
            'dead_links': [],
            'seo_metrics': { 'title': None, 'meta_description': None, 'headings': [] },
            'javascript_errors': []
        }

def generate_report(analysis_data, template_filename="report_template.html", output_path="report.html"):
    """
    Generates an HTML report from analysis data using a Jinja2 template.

    Args:
        analysis_data (dict): The data returned by analyze_url.
        template_filename (str): The filename of the Jinja2 template.
                                 Assumed to be in the 'website_analyzer' directory.
        output_path (str): The path to save the generated HTML report.

    Returns:
        str: The output_path if successful, None otherwise.
    """
    try:
        env = Environment(
            loader=FileSystemLoader('website_analyzer'),
            autoescape=select_autoescape(['html', 'xml'])
        )
        template = env.get_template(template_filename)

        context = {
            'URL': analysis_data.get('url'),
            'ERROR_MESSAGE': analysis_data.get('error'),
            'LOAD_TIME': analysis_data.get('load_time'),
            'STATUS_CODE': analysis_data.get('status_code'),
            'SEO_TITLE': analysis_data.get('seo_metrics', {}).get('title'),
            'SEO_META_DESCRIPTION': analysis_data.get('seo_metrics', {}).get('meta_description'),
            'SEO_HEADINGS': analysis_data.get('seo_metrics', {}).get('headings'),
            'DEAD_LINKS': analysis_data.get('dead_links'),
            'JAVASCRIPT_ERRORS': analysis_data.get('javascript_errors')
        }

        html_output = template.render(context)

        with open(output_path, 'w', encoding='utf-8') as f:
            f.write(html_output)

        return output_path

    except TemplateNotFound:
        print(f"Error: Template '{template_filename}' not found. Ensure it is in the 'website_analyzer' directory.")
        return None
    except Exception as e:
        print(f"Error generating report: {e}")
        return None

if __name__ == '__main__':
    try:
        parser = argparse.ArgumentParser(description="Analyzes a website for SEO metrics, dead links, and load time.")
        parser.add_argument("url", help="The URL to analyze.")
        parser.add_argument("-o", "--output", default="report.html", help="Output HTML report file name (default: report.html).")

        args = parser.parse_args()

        print(f"Analyzing {args.url}...")

        analysis_data = analyze_url(args.url)

        if analysis_data:
            report_file = generate_report(analysis_data, output_path=args.output)
            if report_file:
                print(f"Analysis complete. Report saved to {report_file}")
            else:
                print("Failed to generate report.")
        else:
            print("Failed to get analysis data. This should not happen as analyze_url always returns a dictionary.")
    except Exception as e:
        print(f"An unexpected error occurred: {e}")
