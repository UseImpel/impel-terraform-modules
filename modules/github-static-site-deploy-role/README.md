# github-static-site-deploy-role

Module version: **0.1.0**. Publish this version from the modules repository
before replacing the temporary workspace-relative source in the environment
roots with a registry/Git tag.

An exact GitHub OIDC trust and least-privilege publication policy for a static
frontend. It can upload/delete objects in one bucket and create invalidations
for one CloudFront distribution; it cannot deploy ECS, push ECR images, or read
secrets.
