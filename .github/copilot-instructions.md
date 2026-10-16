This file contains instructions for GitHub Copilot specific to this project.

The onsite-print-web-server is builds a nginx-based server for serving the web 
applications.

The web applications are served through this nginx-based server, ensuring efficient delivery and proper handling of static assets.

There is also a backend for the web applications, handling business logic, and API endpoints.

Last there is the database layer, which stores and manages the persistent data required by the backend and web applications. This layered architecture ensures a clear separation of concerns, making the system more maintainable and scalable.

## API design reference

The previous version's API is documented at
https://api.printerboks.dk/api/v1/docs.
When implementing or changing the onsite-print API, consult that reference and
replicate its design where it makes sense for this tool. Reuse relevant endpoint
conventions, field names, request/response structures, and behavior rather than
inventing alternatives without checking the reference. Do not blindly copy
legacy behavior or change the current `/api/v2` prefix; explain meaningful
deviations and clarify incompatible requirements with the user.