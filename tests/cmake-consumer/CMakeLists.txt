cmake_minimum_required(VERSION 3.20)
project(openssl_sdk_consumer C)

find_package(OpenSSL 3.5.8 EXACT CONFIG REQUIRED)

add_executable(openssl_sdk_consumer main.c)
target_link_libraries(openssl_sdk_consumer PRIVATE OpenSSL::Crypto)
