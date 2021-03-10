import argparse
from base64 import b64decode
import json
import os
from yaml import dump, Dumper


def parse_args():
    parser = argparse.ArgumentParser(description='Convert MSP from json file to a folder structure with files as required by configtxgen')
    parser.add_argument('--dir', type=str, default=".", help="the output directory, default is the current directory")
    parser.add_argument('input_file', type=str, help="the input json file")
    return parser.parse_args()


def write_pem_certs(rootdir, prefix, base64certs):
    os.mkdir(rootdir)
    base64cert_names = {}
    for index, cert in enumerate(base64certs):
        fname = '{0}-{1}-cert.pem'.format(prefix, index)
        if len(base64certs) == 1:
            fname = '{0}-cert.pem'.format(prefix)
        base64cert_names[cert] = fname
        pem = b64decode(cert)
        with open(os.path.join(rootdir, fname), 'wb') as certfile:
            certfile.write(pem)
    return base64cert_names


def upperfirst(s):
    return s[0].upper() + s[1:]


def main():
    args = parse_args()

    print('Trying to create the MSP folder structure from file {}'.format(args.input_file))
    output_dir = os.path.abspath(args.dir)
    if not os.path.exists(output_dir):
        os.mkdir(output_dir)

    try:
        with open(args.input_file, 'r') as infile:
            data = json.load(infile)
            if 'type' not in data or data['type'] != 'msp':
                print('The input is not a MSP json file')
                return
            print('MSP ID: {0}'.format(data['msp_id']))
            # admincerts
            if 'admins' in data:
                write_pem_certs(os.path.join(output_dir, 'admincerts'), 'admin', data['admins'])

            # cacerts
            cacert_names = None
            if 'root_certs' in data:
                cacert_names = write_pem_certs(os.path.join(output_dir, 'cacerts'), 'ca', data['root_certs'])

            # tlscacerts
            if 'tls_root_certs' in data:
                write_pem_certs(os.path.join(output_dir, 'tlscacerts'), 'tlsca', data['tls_root_certs'])

            # config.yaml
            if 'fabric_node_ous' in data:
                # generate config.yaml file
                node_ous_json = data['fabric_node_ous']
                node_ous = {}
                if 'enable' in node_ous_json:
                    node_ous['Enable'] = node_ous_json['enable']
                    del node_ous_json['enable']

                for key, val in node_ous_json.items():
                    if not key.endswith('_ou_identifier'):
                        print('Unknown key "{}", skip it...'.format(key))
                        continue
                    ou_section = {}
                    ou_section['Certificate'] = os.path.join('cacerts', cacert_names[val['certificate']])
                    ou_section['OrganizationalUnitIdentifier'] = val['organizational_unit_identifier']
                    node_ous['{0}OUIdentifier'.format(upperfirst(key.split('_')[0]))] = ou_section
                yaml_data = dump({'NodeOUs': node_ous}, Dumper=Dumper)
                with open(os.path.join(output_dir, 'config.yaml'), 'w') as yamlout:
                    yamlout.write(yaml_data)
    except IOError as err:
        print('IO error: {0}'.format(err))


if __name__ == '__main__':
    main()
