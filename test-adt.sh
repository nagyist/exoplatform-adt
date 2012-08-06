#!/bin/bash -eu

function test-adt() {
  export PRODUCT_NAME=$1
  export PRODUCT_VERSION=$2
  ./adt.sh deploy
  ./adt.sh start
  if $ADT_TESTS_OPEN_BROWSER; then  
    open http://localhost:8080
  fi
  sleep 30
  ./adt.sh stop
  ./adt.sh undeploy
}

test-adt cs       2.1.9
test-adt cs       2.2.9  
test-adt ecms     2.1.9
test-adt ecms     2.3.7
test-adt exogtn   3.1.14-PLF-SNAPSHOT
test-adt exogtn   3.2.4-PLF
test-adt gatein   3.4.0.Final-SNAPSHOT
test-adt ks       2.1.9
test-adt ks       2.2.9
test-adt plf      3.0.9
test-adt plf      3.5.3
test-adt plf      4.0.0.Alpha1-SNAPSHOT
test-adt social   1.1.9
test-adt social   1.2.9
test-adt webos    2.0.6-SNAPSHOT
test-adt compint  3.5.0-SNAPSHOT
test-adt docs     1.1-SNAPSHOT
test-adt plfcom   3.5.3
test-adt plftrial 3.5.3