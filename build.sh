#!/bin/bash

# Variables
DFU_UTIL_VERSION="0.11"
DFU_UTIL_TAR="dfu-util-${DFU_UTIL_VERSION}.tar.gz"
DFU_UTIL_URL="https://dfu-util.sourceforge.net/releases/${DFU_UTIL_TAR}"
DFU_UTIL_FOLDER="dfu-util-${DFU_UTIL_VERSION}"
INSTALL_BASE_PATH="/tmp"
OS_NAME=$(uname -s)
ARCHITECTURE=$(uname -m)
LIBUSB_VERSION="1.0.22"
LIBUSB_URL="https://github.com/libusb/libusb/releases/download/v${LIBUSB_VERSION}/libusb-${LIBUSB_VERSION}.tar.bz2"
LIBUSB_TAR="libusb-${LIBUSB_VERSION}.tar.bz2"
LIBUSB_FOLDER="libusb-${LIBUSB_VERSION}"

# Create the install path with version, OS name, and architecture
INSTALL_PATH="${INSTALL_BASE_PATH}/dfu-util-${DFU_UTIL_VERSION}-${OS_NAME}-${ARCHITECTURE}"
echo "Install path will be: $INSTALL_PATH"

# Function to check if required applications are installed
check_dependencies() {
  local dependencies=("libudev-dev" "autoconf" "pkg-config" "patchelf")
  for dep in "${dependencies[@]}"; do
    if ! dpkg -l | grep -q "$dep"; then
      echo "Error: $dep is not installed. Please install it and try again."
      exit 1
    fi
  done
  echo "All required dependencies are installed."
}

# Function to download and build libusb dependency in the same folder as dfu-util
install_libusb() {
  echo "Checking if libusb is already built in $INSTALL_PATH..."

  # If libusb is already built and installed, skip the build process
  if [ -d "$INSTALL_PATH/lib/pkgconfig" ]; then
    echo "libusb is already installed in $INSTALL_PATH. Skipping build."
    export PKG_CONFIG_PATH="${INSTALL_PATH}/lib/pkgconfig:$PKG_CONFIG_PATH"
    echo "PKG_CONFIG_PATH set to $PKG_CONFIG_PATH"
    return
  fi

  echo "Downloading and building libusb..."

  # Download libusb tarball if not already downloaded
  if [ ! -f "$LIBUSB_TAR" ]; then
    wget "$LIBUSB_URL"
    if [ $? -ne 0 ]; then
      echo "Failed to download libusb. Exiting."
      exit 1
    fi
  fi

  # Extract the tarball if not already extracted
  if [ ! -d "$LIBUSB_FOLDER" ]; then
    echo "Extracting libusb..."
    tar -xjf "$LIBUSB_TAR"
    if [ $? -ne 0 ]; then
      echo "Failed to extract libusb. Exiting."
      exit 1
    fi
  fi

  # Navigate to the extracted folder and build libusb
  cd "$LIBUSB_FOLDER" || exit
  echo "Building libusb..."

  # No need to run ./autogen.sh, directly configure
  ./configure --prefix="$INSTALL_PATH"
  if [ $? -ne 0 ]; then
    echo "configure failed for libusb. Exiting."
    exit 1
  fi

  # Compile and install libusb
  make && make install
  if [ $? -ne 0 ]; then
    echo "Failed to build or install libusb. Exiting."
    exit 1
  fi

  echo "libusb successfully built and installed to $INSTALL_PATH"

  # Set PKG_CONFIG_PATH to include libusb's pkgconfig directory
  export PKG_CONFIG_PATH="${INSTALL_PATH}/lib/pkgconfig:$PKG_CONFIG_PATH"
  echo "PKG_CONFIG_PATH set to $PKG_CONFIG_PATH"

  # Navigate back to the original directory
  cd ..
}

# Function to download and extract dfu-util tarball
download_dfu_util() {
  echo "Downloading dfu-util..."

  # Download dfu-util tarball if not already downloaded
  if [ ! -f "$DFU_UTIL_TAR" ]; then
    wget "$DFU_UTIL_URL"
    if [ $? -ne 0 ]; then
      echo "Failed to download dfu-util. Exiting."
      exit 1
    fi
  fi

  # Extract the dfu-util tarball if not already extracted
  if [ ! -d "$DFU_UTIL_FOLDER" ]; then
    echo "Extracting dfu-util..."
    tar -xzf "$DFU_UTIL_TAR"
    if [ $? -ne 0 ]; then
      echo "Failed to extract dfu-util. Exiting."
      exit 1
    fi
  fi
}

# Check if required applications are installed
# check_dependencies

# Call the function to install libusb dependency in the same folder as dfu-util
install_libusb

# Download and extract dfu-util tarball
download_dfu_util

# Navigate to the extracted dfu-util folder
cd "$DFU_UTIL_FOLDER" || exit

# Run the configure script for dfu-util with the generated install path
echo "Running ./configure --prefix=$INSTALL_PATH..."
./configure --prefix="$INSTALL_PATH"
if [ $? -ne 0 ]; then
  echo "Configuration failed for dfu-util. Exiting."
  exit 1
fi

# Build and install dfu-util
echo "Building and installing dfu-util..."
make && make install-exec
if [ $? -ne 0 ]; then
  echo "Failed to build or install dfu-util. Exiting."
  exit 1
fi

# Modify RPATH for dfu-util binaries
DFU_UTIL_BIN="$INSTALL_PATH/bin/dfu-util"
DFU_SUFFIX_BIN="$INSTALL_PATH/bin/dfu-suffix"
DFU_PREFIX_BIN="$INSTALL_PATH/bin/dfu-prefix"

if [ "$OS_NAME" == "Linux" ]; then
  echo "Patching $DFU_UTIL_BIN with patchelf for Linux..."
  patchelf --set-rpath '$ORIGIN/../lib/' "$DFU_UTIL_BIN"
  if [ $? -ne 0 ]; then
    echo "Failed to patch dfu-util binary with patchelf. Exiting."
    exit 1
  fi
  echo "RPATH set to '$ORIGIN/../lib/' in dfu-util binary."
elif [ "$OS_NAME" == "Darwin" ]; then
  echo "Modifying library path using install_name_tool for macOS..."

  LIBUSB_DYLIB="$INSTALL_PATH/lib/libusb-1.0.0.dylib"

  if [ -f "$LIBUSB_DYLIB" ]; then
    # Change the reference to libusb to use a relative path from the dfu-util binary location
    install_name_tool -change "$LIBUSB_DYLIB" "@loader_path/../lib/libusb-1.0.0.dylib" "$DFU_UTIL_BIN"
    if [ $? -ne 0 ]; then
      echo "Failed to modify dfu-util binary with install_name_tool. Exiting."
      exit 1
    fi
    echo "Library path set to '@loader_path/../lib/libusb-1.0.0.dylib' in dfu-util binary."
  else
    echo "Error: Expected libusb library at $LIBUSB_DYLIB not found."
    exit 1
  fi
fi

# Navigate back to the original directory
cd ..

# Pack everything into a tar.gz archive
ARCHIVE_NAME="tool-dfuutil-${DFU_UTIL_VERSION}-${OS_NAME}-${ARCHITECTURE}.tar.gz"
echo "Packing installed files into $ARCHIVE_NAME..."
tar -czf "$ARCHIVE_NAME" -C "$INSTALL_BASE_PATH" "$(basename "$INSTALL_PATH")"
if [ $? -ne 0 ]; then
  echo "Failed to create archive $ARCHIVE_NAME. Exiting."
  exit 1
fi

echo "dfu-util downloaded, dependencies installed, dfu-util built, installed, and patched successfully!"

echo "Library dependencies dfu-util:"
otool -L $DFU_UTIL_BIN

echo "Library dependencies dfu-suffix:"
otool -L $DFU_SUFFIX_BIN

echo "Library dependencies dfu-prefix:"
otool -L $DFU_PREFIX_BIN

echo "Prepared files:"
ls -alR $INSTALL_PATH

echo "All files have been packed into $ARCHIVE_NAME."

ls -al

# Test the binaries

mv $INSTALL_PATH ~/relocated-package
otool -L ~/relocated-package/bin/dfu-util
~/relocated-package/bin/dfu-util --help

otool -L ~/relocated-package/bin/dfu-suffix
~/relocated-package/bin/dfu-suffix --help

otool -L ~/relocated-package/bin/dfu-prefix
~/relocated-package/bin/dfu-prefix --help