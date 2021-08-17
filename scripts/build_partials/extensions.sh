# Function to enable the extensions in all SAPI.
enable_extension() {
  extension=$1
  mod_file="${mods_dir:?}"/"$extension".ini

  # Remove any existing extension configuration.
  sed -i "/$extension/d" "${ini_file[@]:?}" "${INSTALL_ROOT:?}"/"${pecl_file:?}"

  # If the extension is present in extension directory...
  # copy it along with its headers to the INSTALL_ROOT
  # This is done manually as pecl has broken packagingroot parameter.
  if [ -e "$ext_dir/$extension.so" ]; then
    # Copy the extension to the INSTALL_ROOT.
    cp -f "$ext_dir"/"$extension".so "$INSTALL_ROOT"/"$ext_dir"

    # Copy the headers for the extension to the INSTALL_ROOT.
    ext_include_dir="$(php-config --include-dir)"/ext/"$extension"
    if [ -d "$ext_include_dir" ]; then
      mkdir -p "$INSTALL_ROOT"/"$ext_include_dir"
      cp -rf "$ext_include_dir" "$INSTALL_ROOT"/"$ext_include_dir"/..
    fi

    # Link the extension mod file for all SAPI.
    priority="$(grep priority "$INSTALL_ROOT"/"$mod_file" | cut -d '=' -f 2)"
    link_ini_file "$mod_file" "$priority-$extension.ini"
  fi
}

# Function to install extensions.
setup_custom_extensions() {
  # Parse the config/extensions/$PHP_VERSION file.
  while read -r extension_config; do
    # Get extension type, name and prefix
    type=$(echo "$extension_config" | cut -d ' ' -f 1)
    extension=$(echo "$extension_config" | cut -d ' ' -f 2)
    echo "::group::$extension"

    # If there is a compatible release on PECL i.e. type is pecl.
    if [ "$type" = "pecl" ]; then
      # Install the extension using PECL
      yes '' 2>/dev/null | "$INSTALL_ROOT"/usr/bin/pecl install -f "$extension"
    # Else install from git repository as per the config.
    elif [ "$type" = "git" ]; then
      # Get repository, tag and compile arguments from the config
      repo=$(echo "$extension_config" | cut -d ' ' -f 3)
      tag=$(echo "$extension_config" | cut -d ' ' -f 4)
      IFS=' ' read -r -a args <<<"$(echo "$extension_config" | cut -d ' ' -f 5-)"

      # Compile and install the extension
      bash scripts/install-extension.sh "$extension" "$repo" "$tag" "$INSTALL_ROOT" "${args[@]}"
    fi

    # Enable the extension for all SAPI.
    enable_extension "${extension%-*}"
    echo "::endgroup::"
  done < config/extensions/"$PHP_VERSION"

  # Disable PCOV by default as Xdebug is enabled.
  find "$INSTALL_ROOT"/etc/php/"$PHP_VERSION" -name '*-pcov.ini' -delete

  # Link php from INSTALL_ROOT to system root.
  link_php
}

# Function to configure extensions
configure_shared_extensions() {
  # Copy all modules to mods-available
  cp -f config/modules/*.ini "$INSTALL_ROOT"/"$mods_dir"/

  # Get the extension directory
  ext_dir="$(php-config"$PHP_VERSION" --extension-dir)"

  # Enable other shared extensions for all SAPI.
  echo "::group::configure_extensions"
  for extension_path in "$ext_dir"/*.so; do
    extension="$(basename "$extension_path" | cut -d '.' -f 1)"
    echo "Adding module file for $extension"
    enable_extension "$extension"
  done
  echo "::endgroup::"

  # Link php from INSTALL_ROOT to system root.
  link_php
}
