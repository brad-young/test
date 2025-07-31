class WebhookTester {
    constructor() {
        this.messages = [];
        this.autoScroll = true;
        this.messageId = 1;
        this.webhookUrl = '';
        
        this.init();
    }

    init() {
        this.setupWebhookUrl();
        this.setupEventListeners();
        this.loadMessages();
        this.startPolling();
    }

    setupWebhookUrl() {
        // For GitHub Pages, we'll use a service like webhook.site
        // In a real implementation, you might want to use a service like:
        // - webhook.site
        // - ngrok
        // - or set up a serverless function
        
        // For now, we'll create a mock URL that users can replace
        const baseUrl = window.location.origin;
        this.webhookUrl = `${baseUrl}/webhook`;
        
        const urlInput = document.getElementById('webhookUrl');
        urlInput.value = this.webhookUrl;
        
        // Add a note about the limitation
        const urlNote = document.querySelector('.url-note');
        urlNote.innerHTML = `
            Use this URL as your webhook endpoint<br>
            <small style="color: #e53e3e;">Note: GitHub Pages only supports static content. 
            For real webhook testing, consider using services like webhook.site or ngrok.</small>
        `;
    }

    setupEventListeners() {
        // Copy URL button
        document.getElementById('copyBtn').addEventListener('click', () => {
            this.copyToClipboard(this.webhookUrl);
        });

        // Clear messages button
        document.getElementById('clearBtn').addEventListener('click', () => {
            this.clearMessages();
        });

        // Auto-scroll toggle
        document.getElementById('autoScrollBtn').addEventListener('click', () => {
            this.toggleAutoScroll();
        });

        // Listen for messages from other tabs/windows
        window.addEventListener('storage', (e) => {
            if (e.key === 'webhook_messages') {
                this.loadMessages();
            }
        });

        // Listen for messages from service workers or other sources
        window.addEventListener('message', (e) => {
            if (e.data && e.data.type === 'webhook_message') {
                this.addMessage(e.data.payload);
            }
        });

        // Add a test button for demonstration
        this.addTestButton();
    }

    addTestButton() {
        const controls = document.querySelector('.controls');
        const testBtn = document.createElement('button');
        testBtn.className = 'test-btn';
        testBtn.innerHTML = '<i class="fas fa-play"></i> Test';
        testBtn.style.cssText = `
            padding: 8px 16px;
            border: 1px solid #e2e8f0;
            background: #48bb78;
            color: white;
            border-radius: 6px;
            cursor: pointer;
            font-size: 0.9rem;
            font-weight: 500;
            transition: all 0.2s ease;
            display: flex;
            align-items: center;
            gap: 6px;
        `;
        
        testBtn.addEventListener('click', () => {
            this.sendTestMessage();
        });
        
        controls.appendChild(testBtn);
    }

    sendTestMessage() {
        const testData = {
            message: "Hello from webhook tester!",
            timestamp: new Date().toISOString(),
            source: "test",
            headers: {
                "Content-Type": "application/json",
                "User-Agent": "WebhookTester/1.0"
            },
            body: {
                event: "test",
                data: {
                    id: Math.random().toString(36).substr(2, 9),
                    message: "This is a test webhook message",
                    timestamp: new Date().toISOString()
                }
            }
        };

        this.addMessage(testData);
    }

    copyToClipboard(text) {
        navigator.clipboard.writeText(text).then(() => {
            const btn = document.getElementById('copyBtn');
            btn.classList.add('success');
            btn.innerHTML = '<i class="fas fa-check"></i> Copied!';
            
            setTimeout(() => {
                btn.classList.remove('success');
                btn.innerHTML = '<i class="fas fa-copy"></i> Copy';
            }, 2000);
        }).catch(err => {
            console.error('Failed to copy: ', err);
            // Fallback for older browsers
            const textArea = document.createElement('textarea');
            textArea.value = text;
            document.body.appendChild(textArea);
            textArea.select();
            document.execCommand('copy');
            document.body.removeChild(textArea);
            
            const btn = document.getElementById('copyBtn');
            btn.classList.add('success');
            btn.innerHTML = '<i class="fas fa-check"></i> Copied!';
            
            setTimeout(() => {
                btn.classList.remove('success');
                btn.innerHTML = '<i class="fas fa-copy"></i> Copy';
            }, 2000);
        });
    }

    addMessage(data) {
        const message = {
            id: this.messageId++,
            timestamp: new Date(),
            data: data
        };

        this.messages.unshift(message);
        this.saveMessages();
        this.renderMessages();
        
        // Notify other tabs
        localStorage.setItem('webhook_messages', JSON.stringify(this.messages));
        localStorage.setItem('webhook_messages_timestamp', Date.now().toString());
    }

    clearMessages() {
        if (confirm('Are you sure you want to clear all messages?')) {
            this.messages = [];
            this.saveMessages();
            this.renderMessages();
            localStorage.removeItem('webhook_messages');
        }
    }

    toggleAutoScroll() {
        this.autoScroll = !this.autoScroll;
        const btn = document.getElementById('autoScrollBtn');
        
        if (this.autoScroll) {
            btn.classList.add('active');
            btn.innerHTML = '<i class="fas fa-arrow-down"></i> Auto-scroll';
        } else {
            btn.classList.remove('active');
            btn.innerHTML = '<i class="fas fa-pause"></i> Auto-scroll';
        }
    }

    saveMessages() {
        try {
            localStorage.setItem('webhook_messages', JSON.stringify(this.messages));
        } catch (e) {
            console.error('Failed to save messages:', e);
        }
    }

    loadMessages() {
        try {
            const saved = localStorage.getItem('webhook_messages');
            if (saved) {
                this.messages = JSON.parse(saved);
                this.messageId = Math.max(...this.messages.map(m => m.id), 0) + 1;
            }
        } catch (e) {
            console.error('Failed to load messages:', e);
            this.messages = [];
        }
        this.renderMessages();
    }

    renderMessages() {
        const container = document.getElementById('messagesContainer');
        
        if (this.messages.length === 0) {
            container.innerHTML = `
                <div class="no-messages">
                    <i class="fas fa-inbox"></i>
                    <p>No messages received yet</p>
                    <p>Send a POST request to your webhook URL to see messages here</p>
                </div>
            `;
            return;
        }

        container.innerHTML = this.messages.map(message => this.renderMessage(message)).join('');
        
        if (this.autoScroll) {
            container.scrollTop = 0;
        }
    }

    renderMessage(message) {
        const time = message.timestamp.toLocaleString();
        const data = message.data;
        
        let content = '';
        let meta = '';
        
        // Handle different types of data
        if (typeof data === 'string') {
            content = data;
        } else if (data.body) {
            content = JSON.stringify(data.body, null, 2);
            if (data.headers) {
                meta = `
                    <div class="message-meta">
                        <div class="meta-item">
                            <i class="fas fa-headers"></i>
                            <span>Headers: ${Object.keys(data.headers).length}</span>
                        </div>
                        <div class="meta-item">
                            <i class="fas fa-clock"></i>
                            <span>${data.timestamp || 'Unknown'}</span>
                        </div>
                        ${data.source ? `
                            <div class="meta-item">
                                <i class="fas fa-tag"></i>
                                <span>${data.source}</span>
                            </div>
                        ` : ''}
                    </div>
                `;
            }
        } else {
            content = JSON.stringify(data, null, 2);
        }

        return `
            <div class="message">
                <div class="message-header">
                    <span class="message-time">${time}</span>
                    <span class="message-id">#${message.id}</span>
                </div>
                <div class="message-content">${this.escapeHtml(content)}</div>
                ${meta}
            </div>
        `;
    }

    escapeHtml(text) {
        const div = document.createElement('div');
        div.textContent = text;
        return div.innerHTML;
    }

    startPolling() {
        // Poll for new messages every 5 seconds
        setInterval(() => {
            this.checkForNewMessages();
        }, 5000);
    }

    checkForNewMessages() {
        // This would typically check with a server or service
        // For now, we'll just check localStorage for cross-tab communication
        const timestamp = localStorage.getItem('webhook_messages_timestamp');
        if (timestamp) {
            const lastCheck = this.lastCheck || 0;
            if (parseInt(timestamp) > lastCheck) {
                this.loadMessages();
                this.lastCheck = parseInt(timestamp);
            }
        }
    }
}

// Initialize the webhook tester when the page loads
document.addEventListener('DOMContentLoaded', () => {
    new WebhookTester();
});

// Add some helpful console messages
console.log(`
🚀 Webhook Tester initialized!

To test webhooks with this static site, you have a few options:

1. Use a service like webhook.site:
   - Go to https://webhook.site
   - Copy the unique URL they provide
   - Use that URL as your webhook endpoint

2. Use ngrok to tunnel to a local server:
   - Set up a simple server locally
   - Use ngrok to expose it: ngrok http 3000
   - Use the ngrok URL as your webhook endpoint

3. Use a serverless function:
   - Deploy a simple function to Vercel/Netlify
   - Have it forward requests to this page via postMessage

The test button will simulate receiving a webhook message.
`); 