import SwiftUI
import WebKit

struct WebView: UIViewRepresentable {
    let htmlFileName: String
    
    func makeUIView(context: Context) -> WKWebView {
        let webView = WKWebView()
        webView.navigationDelegate = context.coordinator
        return webView
    }
    
    func updateUIView(_ webView: WKWebView, context: Context) {
        // Debug: Print available resources in bundle
        if let resourcePath = Bundle.main.resourcePath {
            print("Bundle resource path: \(resourcePath)")
        }
        
        // Try to find the HTML file
        if let htmlPath = Bundle.main.path(forResource: htmlFileName, ofType: "html") {
            print("Found HTML file at: \(htmlPath)")
            do {
                let htmlString = try String(contentsOfFile: htmlPath, encoding: .utf8)
                webView.loadHTMLString(htmlString, baseURL: Bundle.main.bundleURL)
                print("Successfully loaded HTML content")
            } catch {
                print("Error reading HTML file: \(error)")
                loadFallbackContent(webView)
            }
        } else {
            print("HTML file not found in bundle. Looking for: \(htmlFileName).html")
            // List all files in bundle for debugging
            if let resourcePath = Bundle.main.resourcePath {
                do {
                    let files = try FileManager.default.contentsOfDirectory(atPath: resourcePath)
                    print("Files in bundle: \(files)")
                } catch {
                    print("Error listing bundle contents: \(error)")
                }
            }
            loadFallbackContent(webView)
        }
    }
    
    private func loadFallbackContent(_ webView: WKWebView) {
        let fallbackHTML = """
        <!DOCTYPE html>
        <html>
        <head>
            <meta name="viewport" content="width=device-width, initial-scale=1.0">
            <style>
                body { 
                    font-family: -apple-system, BlinkMacSystemFont, sans-serif; 
                    padding: 20px; 
                    line-height: 1.6; 
                    max-width: 800px;
                    margin: 0 auto;
                }
                h1 { color: #007AFF; }
                .error { color: #FF3B30; }
                .info { background-color: #f0f0f0; padding: 15px; border-radius: 8px; margin: 20px 0; }
            </style>
        </head>
        <body>
            <h1>Privacy Policy</h1>
            <div class="info">
                <p><strong>Privacy policy content could not be loaded.</strong></p>
                <p>This might be because:</p>
                <ul>
                    <li>The privacy.html file is not included in the app bundle</li>
                    <li>The file name is different than expected</li>
                    <li>There's an issue with the file encoding</li>
                </ul>
                <p>Please contact support at \(HelpAndSupport.supportEmail) for assistance.</p>
            </div>
            
            <h2>Smart Inventory Privacy Policy</h2>
            <p>This is a placeholder privacy policy. The actual privacy policy content should be loaded from the privacy.html file.</p>
            
            <h3>Data Collection</h3>
            <p>Smart Inventory collects minimal data necessary for app functionality:</p>
            <ul>
                <li>Inventory data you create</li>
                <li>Storage information</li>
                <li>App usage analytics (anonymized)</li>
            </ul>
            
            <h3>Data Usage</h3>
            <p>Your data is used solely for:</p>
            <ul>
                <li>Providing inventory management features</li>
                <li>Improving app performance</li>
                <li>Technical support when needed</li>
            </ul>
            
            <h3>Data Security</h3>
            <p>We implement industry-standard security measures to protect your data.</p>
            
            <h3>Contact</h3>
            <p>For privacy-related questions, contact us at \(HelpAndSupport.supportEmail)</p>
        </body>
        </html>
        """
        webView.loadHTMLString(fallbackHTML, baseURL: nil)
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, WKNavigationDelegate {
        var parent: WebView
        
        init(_ parent: WebView) {
            self.parent = parent
        }
        
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            // Inject custom CSS for better styling
            let css = """
            body {
                font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
                line-height: 1.6;
                color: #333;
                max-width: 800px;
                margin: 0 auto;
                padding: 20px;
            }
            h1, h2, h3 {
                color: #007AFF;
                margin-top: 30px;
                margin-bottom: 15px;
            }
            p {
                margin-bottom: 15px;
            }
            ul, ol {
                margin-bottom: 15px;
                padding-left: 20px;
            }
            li {
                margin-bottom: 5px;
            }
            a {
                color: #007AFF;
                text-decoration: none;
            }
            a:hover {
                text-decoration: underline;
            }
            """
            
            let js = """
            var style = document.createElement('style');
            style.innerHTML = '\(css)';
            document.head.appendChild(style);
            """
            
            webView.evaluateJavaScript(js, completionHandler: nil)
        }
        
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            // Handle external links (mailto, http, https)
            if let url = navigationAction.request.url {
                if url.scheme == "mailto" || url.scheme == "http" || url.scheme == "https" {
                    // Open external links in Safari
                    UIApplication.shared.open(url)
                    decisionHandler(.cancel)
                    return
                }
            }
            decisionHandler(.allow)
        }
    }
}

struct PrivacyPolicyView: View {
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            WebView(htmlFileName: "privacy")
                .navigationTitle("Privacy Policy")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("Done") {
                            dismiss()
                        }
                    }
                }
        }
    }
}

#Preview {
    PrivacyPolicyView()
} 