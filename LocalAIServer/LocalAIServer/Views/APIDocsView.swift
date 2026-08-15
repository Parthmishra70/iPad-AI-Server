//
//  APIDocsView.swift
//  LocalAIServer
//
//  API documentation screen showing endpoints and usage examples
//

import SwiftUI

struct APIDocsView: View {
    @EnvironmentObject var serverManager: ServerManager
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Base URL Section
                BaseURLSection()
                
                // Authentication Section
                AuthSection()
                
                // Endpoints Section
                EndpointsSection()
                
                // Code Examples Section
                CodeExamplesSection()
            }
            .padding()
        }
        .navigationTitle("API Documentation")
    }
}

// MARK: - Base URL Section

struct BaseURLSection: View {
    @EnvironmentObject var serverManager: ServerManager
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label {
                Text("Base URL")
                    .font(.headline)
            } icon: {
                Image(systemName: "link")
                    .foregroundColor(.blue)
            }
            
            if let endpoint = serverManager.apiEndpoint {
                CodeBlock(text: endpoint)
                
                Text("The base URL for all API requests. Replace with your iPad's IP address.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                Text("Start the server to see the base URL")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
}

// MARK: - Authentication Section

struct AuthSection: View {
    @EnvironmentObject var apiKeyService: APIKeyService
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label {
                Text("Authentication")
                    .font(.headline)
            } icon: {
                Image(systemName: "key.fill")
                    .foregroundColor(.orange)
            }
            
            Text("All endpoints except `/health` require API key authentication.")
                .font(.body)
            
            CodeBlock(text: "Authorization: Bearer YOUR_API_KEY")
            
            if let key = apiKeyService.getKey() {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Your API Key:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Text(key)
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                }
                .padding(8)
                .background(Color(.systemBackground))
                .cornerRadius(8)
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
}

// MARK: - Endpoints Section

struct EndpointsSection: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label {
                Text("Endpoints")
                    .font(.headline)
            } icon: {
                Image(systemName: "network")
                    .foregroundColor(.green)
            }
            
            // Health Endpoint
            EndpointCard(
                method: "GET",
                path: "/health",
                description: "Check server health status",
                requiresAuth: false,
                exampleResponse: """
                {
                  "status": "ok",
                  "model": "gemma",
                  "device": "iPad",
                  "inference": "local"
                }
                """
            )
            
            // List Models Endpoint
            EndpointCard(
                method: "GET",
                path: "/v1/models",
                description: "List available models",
                requiresAuth: true,
                exampleResponse: """
                {
                  "object": "list",
                  "data": [
                    {
                      "id": "gemma",
                      "object": "model",
                      "owned_by": "local"
                    }
                  ]
                }
                """
            )
            
            // Chat Completions Endpoint
            EndpointCard(
                method: "POST",
                path: "/v1/chat/completions",
                description: "Generate chat completions",
                requiresAuth: true,
                requestBody: """
                {
                  "model": "gemma",
                  "messages": [
                    {
                      "role": "user",
                      "content": "Explain machine learning"
                    }
                  ],
                  "temperature": 0.7,
                  "max_tokens": 512,
                  "stream": false
                }
                """,
                exampleResponse: """
                {
                  "id": "chatcmpl-abc123",
                  "object": "chat.completion",
                  "choices": [
                    {
                      "index": 0,
                      "message": {
                        "role": "assistant",
                        "content": "Machine learning is..."
                      },
                      "finish_reason": "stop"
                    }
                  ]
                }
                """
            )
            
            // Streaming Info
            StreamingInfoCard()
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
}

// MARK: - Endpoint Card

struct EndpointCard: View {
    let method: String
    let path: String
    let description: String
    let requiresAuth: Bool
    var requestBody: String? = nil
    let exampleResponse: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(method)
                    .font(.caption.bold())
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(methodColor)
                    .foregroundColor(.white)
                    .cornerRadius(4)
                
                Text(path)
                    .font(.system(.body, design: .monospaced))
                    .fontWeight(.medium)
                
                if requiresAuth {
                    Image(systemName: "key.fill")
                        .font(.caption)
                        .foregroundColor(.orange)
                }
            }
            
            Text(description)
                .font(.caption)
                .foregroundColor(.secondary)
            
            if let body = requestBody {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Request Body:")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    CodeBlock(text: body)
                }
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text("Response:")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                CodeBlock(text: exampleResponse)
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(8)
    }
    
    private var methodColor: Color {
        switch method {
        case "GET": return .blue
        case "POST": return .green
        case "PUT": return .orange
        case "DELETE": return .red
        default: return .gray
        }
    }
}

// MARK: - Streaming Info Card

struct StreamingInfoCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "waveform")
                    .foregroundColor(.purple)
                
                Text("Streaming Support")
                    .font(.headline)
            }
            
            Text("Set `\"stream\": true` in your request to receive streaming responses via Server-Sent Events (SSE).")
                .font(.body)
            
            CodeBlock(text: """
            data: {"choices":[{"delta":{"content":"Machine"}}]}
            
            data: {"choices":[{"delta":{"content":" learning"}}]}
            
            data: {"choices":[{"delta":{"content":" is"}}]}
            
            data: [DONE]
            """)
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(8)
    }
}

// MARK: - Code Examples Section

struct CodeExamplesSection: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label {
                Text("Code Examples")
                    .font(.headline)
            } icon: {
                Image(systemName: "terminal.fill")
                    .foregroundColor(.purple)
            }
            
            // Python Example
            CodeExampleCard(
                language: "Python",
                code: """
                import requests
                
                url = "http://192.168.1.20:8080/v1/chat/completions"
                
                payload = {
                    "model": "gemma",
                    "messages": [
                        {
                            "role": "user",
                            "content": "What is computer vision?"
                        }
                    ],
                    "temperature": 0.7,
                    "max_tokens": 512
                }
                
                headers = {
                    "Authorization": "Bearer YOUR_API_KEY",
                    "Content-Type": "application/json"
                }
                
                response = requests.post(url, json=payload, headers=headers)
                
                print(response.json())
                """
            )
            
            // cURL Example
            CodeExampleCard(
                language: "cURL",
                code: """
                curl http://192.168.1.20:8080/v1/chat/completions \\
                  -H "Content-Type: application/json" \\
                  -H "Authorization: Bearer YOUR_API_KEY" \\
                  -d '{
                    "model": "gemma",
                    "messages": [
                      {"role": "user", "content": "Hello!"}
                    ],
                    "temperature": 0.7
                  }'
                """
            )
            
            // OpenAI SDK Example
            CodeExampleCard(
                language: "Python (OpenAI SDK)",
                code: """
                from openai import OpenAI
                
                client = OpenAI(
                    api_key="YOUR_API_KEY",
                    base_url="http://192.168.1.20:8080/v1"
                )
                
                response = client.chat.completions.create(
                    model="gemma",
                    messages=[
                        {"role": "user", "content": "Explain quantum computing"}
                    ]
                )
                
                print(response.choices[0].message.content)
                """
            )
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
}

// MARK: - Code Block

struct CodeBlock: View {
    let text: String
    
    var body: some View {
        Text(text)
            .font(.caption.monospaced())
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(Color(.systemBackground))
            .cornerRadius(8)
            .textSelection(.enabled)
    }
}

// MARK: - Code Example Card

struct CodeExampleCard: View {
    let language: String
    let code: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(language)
                .font(.caption.bold())
                .foregroundColor(.secondary)
            
            CodeBlock(text: code)
        }
    }
}

#Preview {
    APIDocsView()
        .environmentObject(ServerManager.shared)
        .environmentObject(APIKeyService.shared)
}
