# Use the latest foundry image
FROM ghcr.io/foundry-rs/foundry

# Copy our source code into the container
WORKDIR /app

# Install Node.js and npm
RUN apk update && apk add nodejs npm

# Copy package files and install dependencies
COPY package*.json ./
RUN npm install

# Build and test the source code
COPY . /app
RUN forge build
RUN chmod +x /app/entrypoint.sh

ENTRYPOINT ["sh", "/app/entrypoint.sh"]
