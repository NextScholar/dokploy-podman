# Create the directory if it doesn't exist
mkdir -p /etc/containers

# Create a default policy.json file
cat > /etc/containers/policy.json << EOF
{
    "default": [
        {
            "type": "insecureAcceptAnything"
        }
    ],
    "transports": {
        "docker": {
            "": [
                {
                    "type": "insecureAcceptAnything"
                }
            ]
        },
        "docker-daemon": {
            "": [
                {
                    "type": "insecureAcceptAnything"
                }
            ]
        }
    }
}
EOF

cat > /etc/containers/registries.conf << EOF
# For more information on this configuration file, see containers-registries.conf(5).
#
# Registries to search for images that are not fully-qualified.
unqualified-search-registries = ["docker.io"]

# Registries that do not use TLS when pulling images or uses self-signed
# certificates.
[[registry]]
location = "docker.io"
EOF