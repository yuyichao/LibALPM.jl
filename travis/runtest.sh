#!/bin/bash

cat > docker_test.sh <<EOF
$(env | grep '^TRAVIS' | sed 's/\(^.*\)/export "\1"/g')
cd "${PWD}"
julia --color=yes -e 'Pkg.clone(pwd()); Pkg.build("LibALPM")'
julia --color=yes --check-bounds=yes -e 'Pkg.test("LibALPM", coverage=true)'
julia --color=yes -e 'cd(Pkg.dir("LibALPM")); Pkg.add("Coverage"); using Coverage; Codecov.submit(process_folder())'
EOF

docker exec -u julia:julia $(cat /docker-name) bash -e "${PWD}/docker_test.sh"
ret=$?
docker kill $(cat /docker-name)
exit $ret
