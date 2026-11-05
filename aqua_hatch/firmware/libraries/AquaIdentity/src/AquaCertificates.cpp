#include "AquaCertificates.h"
#include <vector>
#include <cstring>
#include <mbedtls/pk.h>
#include <mbedtls/ecp.h>
#include <mbedtls/x509_crt.h>
#include <mbedtls/oid.h>

namespace aqua_cert {
namespace {
struct Key { mbedtls_pk_context value; Key(){mbedtls_pk_init(&value);} ~Key(){mbedtls_pk_free(&value);} };
struct Cert { mbedtls_x509_crt value; Cert(){mbedtls_x509_crt_init(&value);} ~Cert(){mbedtls_x509_crt_free(&value);} };
struct Writer { mbedtls_x509write_cert value; Writer(){mbedtls_x509write_crt_init(&value);} ~Writer(){mbedtls_x509write_crt_free(&value);} };
bool parse(Key &key,const std::string &pem,Random random,void *context){return mbedtls_pk_parse_key(&key.value,(const unsigned char*)pem.c_str(),pem.size()+1,nullptr,0,random,context)==0;}
}
bool generateKey(Random random,void *context,std::string &pem){
  Key key;
  if(mbedtls_pk_setup(&key.value,mbedtls_pk_info_from_type(MBEDTLS_PK_ECKEY))!=0 ||
     mbedtls_ecp_gen_key(MBEDTLS_ECP_DP_SECP256R1,mbedtls_pk_ec(key.value),random,context)!=0)return false;
  std::vector<unsigned char> output(1024);
  if(mbedtls_pk_write_key_pem(&key.value,output.data(),output.size())!=0)return false;
  pem=(const char*)output.data();return true;
}
bool issue(const std::string &subjectKey,const std::string &issuerKey,
           const std::string &subject,const std::string &issuer,
           const std::string &hostname,bool authority,
           const char *notBefore,const char *notAfter,
           Random random,void *context,std::string &certificate){
  Key subjectPk,issuerPk;Writer writer;
  if(!parse(subjectPk,subjectKey,random,context)||!parse(issuerPk,issuerKey,random,context))return false;
  auto *w=&writer.value;
  mbedtls_x509write_crt_set_version(w,MBEDTLS_X509_CRT_VERSION_3);
  mbedtls_x509write_crt_set_md_alg(w,MBEDTLS_MD_SHA256);
  mbedtls_x509write_crt_set_subject_key(w,&subjectPk.value);
  mbedtls_x509write_crt_set_issuer_key(w,&issuerPk.value);
  unsigned char serialBytes[16];if(random(context,serialBytes,sizeof(serialBytes))!=0)return false;
  serialBytes[0]=(serialBytes[0]&0x7f)|1;
  if(mbedtls_x509write_crt_set_serial_raw(w,serialBytes,sizeof(serialBytes))!=0)return false;
  if(mbedtls_x509write_crt_set_subject_name(w,subject.c_str())!=0 ||
     mbedtls_x509write_crt_set_issuer_name(w,issuer.c_str())!=0 ||
     mbedtls_x509write_crt_set_validity(w,notBefore,notAfter)!=0 ||
     mbedtls_x509write_crt_set_basic_constraints(w,authority,authority?0:-1)!=0 ||
     mbedtls_x509write_crt_set_key_usage(w,authority?(MBEDTLS_X509_KU_KEY_CERT_SIGN|MBEDTLS_X509_KU_CRL_SIGN):MBEDTLS_X509_KU_DIGITAL_SIGNATURE)!=0 ||
     mbedtls_x509write_crt_set_subject_key_identifier(w)!=0 ||
     mbedtls_x509write_crt_set_authority_key_identifier(w)!=0)return false;
  if(!authority){
    if(hostname.empty()||hostname.size()>100)return false;
    std::vector<unsigned char> san={0x30,(unsigned char)(hostname.size()+2),0x82,(unsigned char)hostname.size()};
    san.insert(san.end(),hostname.begin(),hostname.end());
    const unsigned char eku[]={0x30,0x0a,0x06,0x08,0x2b,0x06,0x01,0x05,0x05,0x07,0x03,0x01};
    if(mbedtls_x509write_crt_set_extension(w,MBEDTLS_OID_SUBJECT_ALT_NAME,MBEDTLS_OID_SIZE(MBEDTLS_OID_SUBJECT_ALT_NAME),0,san.data(),san.size())!=0 ||
       mbedtls_x509write_crt_set_extension(w,MBEDTLS_OID_EXTENDED_KEY_USAGE,MBEDTLS_OID_SIZE(MBEDTLS_OID_EXTENDED_KEY_USAGE),0,eku,sizeof(eku))!=0)return false;
  }
  std::vector<unsigned char> output(2048);
  if(mbedtls_x509write_crt_pem(w,output.data(),output.size(),random,context)!=0)return false;
  certificate=(const char*)output.data();return true;
}
bool publicDer(const std::string &pem,std::string &der){
  Cert cert;if(mbedtls_x509_crt_parse(&cert.value,(const unsigned char*)pem.c_str(),pem.size()+1)!=0)return false;
  der.assign((const char*)cert.value.raw.p,cert.value.raw.len);return true;
}
bool matchingKey(const std::string &certificate,const std::string &key,Random random,void *context){
  Cert cert;Key pk;
  return mbedtls_x509_crt_parse(&cert.value,(const unsigned char*)certificate.c_str(),certificate.size()+1)==0 &&
    parse(pk,key,random,context) && mbedtls_pk_check_pair(&cert.value.pk,&pk.value,random,context)==0;
}
}
