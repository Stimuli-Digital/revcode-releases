# Microsoft Store installer downloads

This dedicated static service serves the existing signed production MSI without an HTTP redirect. Partner Center rejects redirecting installer URLs, including GitHub release download URLs.

The Docker build fetches the public release artifact and verifies its SHA-256 before creating the image. Nginx serves that exact file, supports HEAD and byte ranges, and never proxies a mutable latest-release link. No application API or customer data is accessible here.

Deploy this directory as the Railway `store-downloads` service in `production-v2`, with port 8080 and health check `/health`. The root URL intentionally returns 404. Existing version paths must remain available and unchanged when adding future releases. Add a checksum-verified artifact and exact nginx location for each new Store version; do not replace a previously submitted MSI.

The landing-page download must only switch to the Microsoft Store distribution path after certification and actual Store installation/update acceptance. This service alone does not establish Store approval or SmartScreen behavior.

Direct installer endpoint: `https://store-downloads-production-v2.up.railway.app/releases/v0.63.7/Revcode_0.63.7_x64_en-US.msi`
