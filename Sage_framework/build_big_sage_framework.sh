BASE_DIR=`pwd`
VERSION=`./get_big_sage_version`
echo Sage Version is ${VERSION}.
REPO=${BASE_DIR}/bigrepo/sage
FILES=${BASE_DIR}/files
BUILD=${BASE_DIR}/build
VERSION_DIR=${BUILD}/Sage.framework/Versions/${VERSION}
CURRENT_DIR=${BUILD}/Sage.framework/Versions/Current
RESOURCE_DIR=${VERSION_DIR}/Resources
KERNEL_DIR="${VERSION_DIR}/Resources/jupyter/kernels/SageMath-${VERSION}"
VENV=venv-python3.9.9
VENV_DIR="local/var/lib/sage/${VENV}"
VENV_PYLIB="${VENV_DIR}/lib/python3.9"
THREEJS_SAGE="${VERSION_DIR}/${VENV_DIR}/share/jupyter/nbextensions/threejs-sage"
# This allows Sage.framework to be a symlink to the framework inside the application.
if ! [ -d "${BUILD}/Sage.framework" ]; then
    mkdir -p "${BUILD}"/Sage.framework
fi

# Clean out everything.
echo Removing old framework ...
rm -rf "${BUILD}"/Sage.framework/*

# Create the bundle directories
mkdir -p "${RESOURCE_DIR}"
ln -s ${VERSION} "${CURRENT_DIR}"
ln -s Versions/Current/Resources "${BUILD}"/Sage.framework/Resources
ln -s ${VENV_DIR} ${VERSION_DIR}/venv

# Create the resource files
cp "${REPO}"/{COPYING.txt,README.md,VERSION.txt} "${RESOURCE_DIR}"
sed "s/__VERSION__/${VERSION}/g" "${FILES}"/Info.plist > "${RESOURCE_DIR}"/Info.plist
cp ${FILES}/pip.conf ${RESOURCE_DIR}
mkdir -p ${VERSION_DIR}/local/{bin,include,lib,etc,libexec}
echo "Copying files ..."
cp -R "${REPO}"/local/bin/ ${VERSION_DIR}/local/bin
cp -R "${REPO}"/local/include/ ${VERSION_DIR}/local/include
cp -R "${REPO}"/local/lib/ ${VERSION_DIR}/local/lib
cp -R "${REPO}"/local/etc/ ${VERSION_DIR}/local/etc
cp -R "${REPO}"/local/libexec/ ${VERSION_DIR}/local/libexec
if [ `uname -m` == arm64 ]; then
    cp -R gfortran/lib ${VERSION_DIR}/local
fi
ln -s lib "${VERSION_DIR}"/local/lib64
mkdir -p ${VERSION_DIR}/local/var/lib/sage/{installed,scripts}
mkdir -p ${VERSION_DIR}/${VENV_DIR}
cp -R "${REPO}"/local/var/lib/sage/installed/ ${VERSION_DIR}/local/var/lib/sage/installed
cp -R "${REPO}"/local/var/lib/sage/scripts/ ${VERSION_DIR}/local/var/lib/sage/scripts
cp -R "${REPO}"/${VENV_DIR}/{bin,lib,include,share} ${VERSION_DIR}/${VENV_DIR}
rm -rf ${VERSION_DIR}/${VENV_DIR}/share/{doc,man}
mkdir -p ${VERSION_DIR}/local/share
for share_dir in `ls "${REPO}"/local/share`; do
    if [ $share_dir != "doc" ]; then
	cp -R "${REPO}"/local/share/$share_dir ${VERSION_DIR}/local/share/$share_dir
    fi
done
# Create the runpath.sh script
echo SAGE_SYMLINK=/var/tmp/sage-${VERSION}-current > ${VERSION_DIR}/local/var/lib/sage/runpath.sh
chmod 755 ${VERSION_DIR}/local/var/lib/sage/runpath.sh

# Copy our modified files into the bundle
if [ $(uname -m) == "arm64" ]; then
    TKINTER=_tkinter.cpython-39-darwin-arm64.so
else
    TKINTER=_tkinter.cpython-39-darwin-x86_64.so
fi
cp -p ${FILES}/page.html ${VERSION_DIR}/${VENV_PYLIB}/site-packages/notebook/templates/page.html
cp -p ${FILES}/{sage,sage-env} ${VERSION_DIR}/${VENV_DIR}/bin
cp -p ${FILES}/kernel.py ${VERSION_DIR}/${VENV_PYLIB}/site-packages/sage/repl/ipython_kernel/kernel.py
sed "s/__VERSION__/${VERSION}/g" "${FILES}"/sage-env-config > "${VERSION_DIR}"/local/bin/sage-env-config
cp "${VERSION_DIR}"/local/bin/sage-env-config ${VERSION_DIR}/${VENV_DIR}/bin
rm -rf ${VERSION_DIR}/${VENV_DIR}/share/jupyter/kernels/sagemath
mkdir -p ${KERNEL_DIR}
sed "s/__VERSION__/${VERSION}/g" "${FILES}"/kernel.json > ${KERNEL_DIR}/kernel.json
cp -p ${FILES}/${TKINTER} ${VERSION_DIR}/${VENV_PYLIB}/lib-dynload/_tkinter.cpython-39-darwin.so
cp ${FILES}/sagedoc.py ${VERSION_DIR}/${VENV_PYLIB}/site-packages/sage/misc/sagedoc.py

# Fix illegal symlinks that point outside of the bundle
rm ${VERSION_DIR}/local/share/gap/{gac,gap}
ln -s ../../bin/gac ${VERSION_DIR}/local/share/gap/gac
ln -s ../../bin/gap ${VERSION_DIR}/local/share/gap/gap
rm -rf ${VERSION_DIR}/local/share/jupyter/kernels/sagemath/doc
rm -f ${VERSION_DIR}/local/share/threejs-sage/threejs-sage
rm -f ${VERSION_DIR}/${VENV_DIR}/share/jupyter/nbextensions/threejs-sage
ln -s ../../../../../../../share/threejs-sage ${VERSION_DIR}/${VENV_DIR}/share/jupyter/nbextensions/threejs-sage

# Fix up rpaths and shebangs 
echo "Patching files ..."
mv files_to_sign files_to_sign.bak
python3 fix_paths.py bigrepo ${VERSION_DIR}/local/bin > files_to_sign
python3 fix_paths.py bigrepo ${VERSION_DIR}/local/lib >> files_to_sign
python3 fix_paths.py bigrepo ${VERSION_DIR}/local/libexec >> files_to_sign
python3 fix_paths.py bigrepo ${VERSION_DIR}/${VENV_DIR}/bin >> files_to_sign
python3 fix_paths.py bigrepo ${VERSION_DIR}/${VENV_DIR}/lib >> files_to_sign

# Fix the absolute symlinks for the GAP packages
pushd ${VERSION_DIR}/local/share/gap/pkg
for pkg in `ls` ; do
  if [[ -L $pkg/bin ]]; then
    rm $pkg/bin ;
    ln -s ../../../../lib/gap/pkg/$pkg/bin $pkg/bin ; 
  fi
done
popd

# Remove xattrs (must be done before signing!)
xattr -rc ${BUILD}/Sage.framework

# Remove byte code
find ${BUILD}/Sage.framework -name '*.pyc' -delete
# Sign the framework.
echo "Signing files ..."
python3 sign_sage.py
# Start sage to create a minimal set of bytecode files.
echo "Starting Sage to create byte code files ..."
${VERSION_DIR}/venv/bin/sage
echo Signing the framework again
python3 sign_sage.py framework
