#!/bin/bash

# Set up the input directories
input_dirs=(/path/to/dir1 /path/to/dir2 /path/to/dir3)

# Set up the output directories
output_dirs=(/path/to/output1 /path/to/output2)

# Set up the maximum size of the backup file in bytes (15 GB in this case)
max_size=$((15*1024*1024*1024))

# Set up the available output directories
available_output_dirs=("${output_dirs[@]}")

# Compress the input directories into a single archive
temp_file=$(mktemp)
tar -czf "$temp_file" "${input_dirs[@]}"

# Ask the user for an encryption password
read -s -p "Enter an encryption password: " encryption_password

# Derive a 256-bit encryption key using PBKDF2 key derivation
salt=$(openssl rand -hex 16) # generate a random 128-bit salt
encryption_key=$(openssl enc -pbkdf2 -pass "pass:$encryption_password" -salt "$salt" -md sha256 -iter 100000 -klen 32)

# Encrypt the archive with AES-256 using openssl
timestamp=$(date +%Y-%m-%d_%H-%M-%S)
encrypted_file="${available_output_dirs[0]}/backup-$timestamp.tar.gz.enc"
openssl enc -aes-256-cbc -salt -in "$temp_file" -out "$encrypted_file" -pass "pass:$encryption_key"

# Check if the encrypted archive is larger than the maximum size
if [[ $(stat -c %s "$encrypted_file") -gt $max_size ]]; then
    # Split the encrypted archive into multiple files if it's larger than the maximum size
    split_size=$((max_size/2)) # split the file in half to create two parts
    split_dir="${available_output_dirs[0]}/$(basename "$encrypted_file")-split"
    mkdir -p "$split_dir"
    split --bytes=$split_size "$encrypted_file" "$split_dir/"
    rm "$encrypted_file" # delete the original file
    # Remove the full output directory from the list of available output directories
    available_output_dirs=("${available_output_dirs[@]/${available_output_dirs[0]}}")
fi

# If the output directory is full, move on to the next one
while [[ -z "$encrypted_file" ]]; do
    # Check if there are any available output directories left
    if [[ "${#available_output_dirs[@]}" -eq 0 ]]; then
        echo "All output directories are full. Please input a new directory or enter 'exit' to quit:"
        read new_output_dir
        if [[ "$new_output_dir" == "exit" ]]; then
            exit 1
        fi
        available_output_dirs+=("$new_output_dir")
    fi
    # Encrypt the archive with AES-256 using openssl and move it to the next available output directory
    timestamp=$(date +%Y-%m-%d_%H-%M-%S)
    encrypted_file="${available_output_dirs[0]}/backup-$timestamp.tar.gz.enc"
    openssl enc -aes-256-cbc -salt -in "$temp_file" -out "$encrypted_file" -pass "pass:$encryption_key"
    # Check if the encrypted archive is larger than the maximum size
    if [[ $(stat -c %s "$encrypted_file") -gt $max_size ]]; then
        # Split the encrypted archive into multiple files if it's larger than the maximum size
        split_size=$((max_size/2)) # split the file in half to
        split_dir="${available_output_dirs[0]}/$(basename "$encrypted_file")-split"
        mkdir -p "$split_dir"
        split --bytes=$split_size "$encrypted_file" "$split_dir/"
        rm "$encrypted_file" # delete the original file
        # Remove the full output directory from the list of available output directories
        available_output_dirs=("${available_output_dirs[@]/${available_output_dirs[0]}}")
    fi
done

# Move the encrypted archive (or its parts) to the output directory
for f in "$split_dir"/*; do
    mv "$f" "${available_output_dirs[0]}/$(basename "$f")"
done

# Create a shell script to decrypt and unarchive the backup file(s)
cat > "${available_output_dirs[0]}/decrypt.sh" << EOF
#!/bin/bash

# Ask the user for the encryption password
read -s -p "Enter the encryption password: " encryption_password

# Derive the encryption key using PBKDF2 key derivation
salt=\$(head -c 16 "${available_output_dirs[0]}"/backup-* | tail -c 16) # extract the salt from the backup file(s)
encryption_key=\$(openssl enc -pbkdf2 -pass "pass:\$encryption_password" -salt "\$salt" -md sha256 -iter 100000 -klen 32)

# Decrypt and unarchive the backup file(s)
for f in "${available_output_dirs[0]}"/*; do
    if [[ "\$f" == *".enc" ]]; then
        decrypted_file="\${f%.enc}"
        openssl enc -aes-256-cbc -d -salt -in "\$f" -out "\$decrypted_file" -pass "pass:\$encryption_key"
        tar -xzf "\$decrypted_file" -C "${available_output_dirs[0]}"
        rm "\$decrypted_file" # delete the decrypted file
    fi
done
EOF

chmod +x "${available_output_dirs[0]}/decrypt.sh" # make the script executable
