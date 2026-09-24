# cloudfront-spa-api

Module version: **0.1.0**. Publish this version from the modules repository
before replacing the temporary workspace-relative source in the environment
roots with a registry/Git tag.

Creates a private, versioned S3 bucket and a CloudFront distribution that
serves a Vite SPA while routing `/api/*` to an HTTPS ALB origin. API requests
are uncached and forward browser credentials, headers, query strings, and all
methods. Use a DNS name covered by the ALB certificate for the API origin; the
shared ALB routes that origin hostname to the API target group. The viewer
certificate must be issued in `us-east-1`.
