#!/usr/bin/env sh

set -eux

build_target="${OMPL_BUILD_TARGET:-linux}"
build_arch="${OMPL_BUILD_ARCH:-x86_64}"
python_version=$(python3 -c 'import sys; v=sys.version_info; print(f"{v.major}.{v.minor}")')
python_include_path=$(python3 -c "from sysconfig import get_paths as gp; print(gp()['include'])")
boost_version="1.85.0"

# Work inside a temporary directory.
cd $(mktemp -d -t "ompl-wheels.XXX")

# Need latest for this PR with Mac fixes:
# https://github.com/ompl/pyplusplus/pull/1
pip install git+https://github.com/ompl/pyplusplus

# NOTE: Hold back numpy<2.0 until Boost.Python integrates required fixes. Not
# done as of boost==1.85.
pip install cmake pygccxml numpy<2 build ninja

if [ "${build_target}" == "linux" ]; then
    # Install CastXML dependency.
    git clone --depth 1 https://github.com/CastXML/CastXML
    pushd CastXML
    mkdir -p build && cd build
    cmake -GNinja -DCMAKE_BUILD_TYPE=Release -DCLANG_RESOURCE_DIR=$(clang -print-resource-dir) ..
    cmake --build .
    ninja install
    popd

    # Install the latest Boost, because it has to be linked to the exact version of
    # Python for which we are building the wheel.
    curl -L "https://boostorg.jfrog.io/artifactory/main/release/${boost_version}/source/boost_${boost_version//./_}.tar.bz2" | tar xj
    echo "using python : ${python_version} ;" >$HOME/user-config.jam
    pushd "boost_${boost_version//./_}"
    ./bootstrap.sh
    ./b2 \
        --with-serialization \
        --with-filesystem \
        --with-system \
        --with-program_options \
        --with-python \
        install
    popd

fi

if [ "${build_target}" == "macos" ]; then
    # For Python development headers
    brew install --overwrite "python@${python_version}"

    # Install the latest Boost, because it has to be linked to the exact version of
    # Python for which we are building the wheel.
    curl -L "https://boostorg.jfrog.io/artifactory/main/release/${boost_version}/source/boost_${boost_version//./_}.tar.bz2" | tar xj
    echo "using python : ${python_version} : : ${python_include_path} ;" >$HOME/user-config.jam
    pushd "boost_${boost_version//./_}"
    ./bootstrap.sh

    if [ "${build_arch}" == "x86_64" ]; then
        sudo ./b2 architecture=x86 address-model=64 cxxflags="-arch x86_64" \
            --with-serialization \
            --with-filesystem \
            --with-system \
            --with-program_options \
            --with-python \
            install
    elif [ "${build_arch}" == "arm64" ]; then
        sudo ./b2 architecture=arm address-model=64 cxxflags="-arch arm64" \
            --with-serialization \
            --with-filesystem \
            --with-system \
            --with-program_options \
            --with-python \
            install
    fi

    popd
fi
