#!/bin/bash

# Set up the input directories
input_dirs=(/path/to/dir1 /path/to/dir2 /path/to/dir3)

# Set up the output directory
output_dir=/path/to/backup

# Set up the maximum size of the backup file in bytes (15 GB in this case)
max_size=$((15*1024*1024*1024))

# Function to find a directory with enough free space
function find_output_dir {
    for dir in "${output_dirs[@]}"; do
        free_space=$(df --output=avail "$dir" | tail -n 1)
        if [[ $free_space -ge $max_size ]]; then
            echo "$dir"
            return
        fi
    done
}

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
encrypted_file="$output_dir/backup-$timestamp.tar.gz.enc"
openssl enc -aes-256-cbc -salt -in "$temp_file" -out "$encrypted_file" -pass "pass:$encryption_key"

# Split the encrypted archive into multiple files if it's larger than the maximum size
if [[ $(stat -c %s "$encrypted_file") -gt $max_size ]]; then
    split_size=$((max_size/2)) # split the file in half to create two parts
    split_dir="$output_dir/$(basename "$encrypted_file")-split"
    mkdir -p "$split_dir"
    split --bytes=$split_size "$encrypted_file" "$split_dir/"
    rm "$encrypted_file" # delete the original file
else
    split_dir="$output_dir"
fi

# Move the encrypted archive (or its parts) to the output directory
for f in "$split_dir"/*; do
    mv "$f" "$output_dir/"
done

# Create a shell script to decrypt and unarchive the backup file(s)
cat > "$output_dir/decrypt.sh" << EOF
#!/bin/bash

# Ask the user for the encryption password
read -s -p "Enter the encryption password: " encryption_password

# Derive the encryption key using PBKDF2 key derivation
salt=\$(head -c 16 "$output_dir"/backup-* | tail -c 16) # extract the salt from the backup file(s)
encryption_key=\$(openssl enc -pbkdf2 -pass "pass:\$encryption_password" -salt "\$salt" -md sha256 -iter 100000 -klen 32)

# Encrypt the archive with AES-256 using openssl
timestamp=$(date +%Y-%m-%d_%H-%M-%S)
output_dir=$(find_output_dir)
while [[ -z $output_dir ]]; do
    read -p "No available output directory with enough space. Enter another directory or type 'exit' to quit: " output_dir
    if [[ $output_dir == "exit" ]]; then
        exit 1
    fi
done

# Decrypt and unarchive the backup file(s)
for f in "$output_dir"/*; do
    if [[ "\$f" == *".enc" ]]; then
        decrypted_file="\${f%.enc}"
        openssl enc -aes-256-cbc -d -salt -in "\$f" -out "\$decrypted_file" -pass "pass:\$encryption_key"
        tar -xzf "\$decrypted_file" -C "$output_dir"
        rm "\$decrypted_file" # delete the decrypted file
    fi
done
EOF

chmod +x "$output_dir/decrypt.sh" # make the script executable
