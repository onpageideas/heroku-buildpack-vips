#!/bin/bash

set -e

# Set vips version
export VIPS_VERSION=8.9.2
export BUILD_PATH=/tmp
export OUT_PATH=$OUT_DIR/app/vendor/vips
export PKG_CONFIG_PATH=$OUT_PATH/lib/pkgconfig:$PKG_CONFIG_PATH
export PATH=$OUT_PATH/bin:$PATH

# Based on https://gist.github.com/chrismdp/6c6b6c825b07f680e710
function putS3 {
  file=$1
  aws_path=$2
  aws_id=$3
  aws_token=$4
  aws_bucket=$5
  date=$(date +"%a, %d %b %Y %T %z")
  acl="x-amz-acl:public-read"
  content_type='application/x-compressed-tar'
  string="PUT\n\n$content_type\n$date\n$acl\n/$aws_bucket$aws_path$file"
  signature=$(echo -en "${string}" | openssl sha1 -hmac "${aws_token}" -binary | base64)
  curl -X PUT -T "$file" \
    -H "Host: $aws_bucket.s3.amazonaws.com" \
    -H "Date: $date" \
    -H "Content-Type: $content_type" \
    -H "$acl" \
    -H "Authorization: AWS ${aws_id}:$signature" \
    "https://$aws_bucket.s3.amazonaws.com$aws_path$file"
  echo "Uploaded to https://$aws_bucket.s3.amazonaws.com$aws_path$file"
}

# These should be set from the outside. A git version and heroku/travis respectively
if [ -z "$VERSION" ]
then
    VERSION="unknown"
fi
if [ -z "$TARGET" ]
then
    TARGET="unknown"
fi

# Remove out path if already exists
rm -Rf $OUT_PATH


###############
#     VIPS    #
###############
function build_vips {
    # Download vips runtime
    curl -L https://github.com/libvips/libvips/releases/download/v$VIPS_VERSION/vips-$VIPS_VERSION.tar.gz -o vips.tar.gz
    # Unzip
    tar -xvf vips.tar.gz
    # Get into vips folder
    cd vips-$VIPS_VERSION
    # Configure build and output everything in /tmp/vips
    ./autogen.sh --prefix $OUT_PATH --enable-shared --disable-static --disable-dependency-tracking \
  --disable-debug --disable-introspection --without-python --without-fftw \
  --without-magick --without-pangoft2 --without-ppm --without-analyze --without-radiance 
    # Make
    make
    # install vips
    make install
}


### Build
cd $BUILD_PATH
build_vips


###############
#    Output   #
###############

# Get into output path
cd $OUT_PATH
# Clean useless files
rm -rf $OUT_PATH/share/{doc,gtk-doc}
# Create dist package
tar -cvzf libvips-${VERSION}-${TARGET}.tgz *

###############
#     S3      #
###############
if [ -z "$AMAZON_API_TOKEN" ];
then
    echo "Amazon API Token not provided, skipping upload";
else
    putS3 "libvips-${VERSION}-${TARGET}.tgz" "/bundles/" $AMAZON_API_ID $AMAZON_API_TOKEN $AMAZON_API_BUCKET
fi
