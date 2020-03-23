#!/bin/bash

vim --version

pushd test/integration

pub get

pub run test
