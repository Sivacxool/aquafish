#include "AquaCertificates.h"
#include <mbedtls/ctr_drbg.h>
#include <mbedtls/entropy.h>
#include <mbedtls/x509_crt.h>
#include <cassert>
#include <fstream>
#include <filesystem>
#include <iostream>
#include <ctime>

namespace fs=std::filesystem;
void save(const fs::path &path,const std::string &value){std::ofstream file(path,std::ios::binary);file<<value;assert(file.good());}
void date(std::time_t value,char out[16]){auto utc=*std::gmtime(&value);std::strftime(out,16,"%Y%m%d%H%M%S",&utc);}
int main(int argc,char **argv){
  assert(argc==2);fs::path root=argv[1];fs::create_directories(root);
  mbedtls_entropy_context entropy;mbedtls_entropy_init(&entropy);
  mbedtls_ctr_drbg_context random;mbedtls_ctr_drbg_init(&random);
  const unsigned char label[]="AquaHatch runtime certificate test";
  assert(mbedtls_ctr_drbg_seed(&random,mbedtls_entropy_func,&entropy,label,sizeof(label))==0);
  char first[16],last[16];auto now=std::time(nullptr);date(now-86400,first);date(now-86400+730LL*86400,last);
  std::string caKey,key,ca,leaf,otherKey,otherCa;
  const std::string subject="O=AquaHatch,CN=AquaHatch CA s3-aabbccddee01";
  const std::string host="aquahatch-s3-aabbccddee01.local";
  auto rng=mbedtls_ctr_drbg_random;
  assert(aqua_cert::generateKey(rng,&random,caKey));
  assert(aqua_cert::generateKey(rng,&random,key));assert(caKey!=key);
  assert(aqua_cert::issue(caKey,caKey,subject,subject,"",true,"20000101000000","20990101000000",rng,&random,ca));
  assert(aqua_cert::issue(key,caKey,"O=AquaHatch,CN="+host,subject,host,false,first,last,rng,&random,leaf));
  assert(aqua_cert::matchingKey(ca,caKey,rng,&random));
  assert(aqua_cert::matchingKey(leaf,key,rng,&random));
  assert(!aqua_cert::matchingKey(leaf,caKey,rng,&random));
  assert(aqua_cert::generateKey(rng,&random,otherKey));
  assert(aqua_cert::issue(otherKey,otherKey,"CN=Other board","CN=Other board","",true,"20000101000000","20990101000000",rng,&random,otherCa));
  assert(ca!=otherCa);
  mbedtls_x509_crt chain,authority,wrong;mbedtls_x509_crt_init(&chain);mbedtls_x509_crt_init(&authority);mbedtls_x509_crt_init(&wrong);
  assert(mbedtls_x509_crt_parse(&chain,(const unsigned char*)leaf.c_str(),leaf.size()+1)==0);
  assert(mbedtls_x509_crt_parse(&authority,(const unsigned char*)ca.c_str(),ca.size()+1)==0);
  assert(mbedtls_x509_crt_parse(&wrong,(const unsigned char*)otherCa.c_str(),otherCa.size()+1)==0);
  uint32_t flags=0;assert(mbedtls_x509_crt_verify(&chain,&authority,nullptr,host.c_str(),&flags,nullptr,nullptr)==0);
  assert(mbedtls_x509_crt_verify(&chain,&authority,nullptr,"wrong-board.local",&flags,nullptr,nullptr)!=0);
  assert(mbedtls_x509_crt_verify(&chain,&wrong,nullptr,host.c_str(),&flags,nullptr,nullptr)!=0);
  save(root/"ca.pem",ca);save(root/"server.pem",leaf);save(root/"server-key.pem",key);save(root/"other-ca.pem",otherCa);
  mbedtls_x509_crt_free(&chain);mbedtls_x509_crt_free(&authority);mbedtls_x509_crt_free(&wrong);
  mbedtls_ctr_drbg_free(&random);mbedtls_entropy_free(&entropy);
  std::cout<<"PASS runtime crypto: independent keys/roots, valid chain/SAN, wrong host/root/key rejected\n";
}
