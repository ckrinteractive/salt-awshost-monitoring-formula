from distutils.version import LooseVersion as _LooseVersion
from salt.utils.decorators import depends

try:
    import boto.utils
    required_boto_version = '2.46.1'
    HAS_BOTO = (_LooseVersion(boto.__version__) >= _LooseVersion(required_boto_version))
except ImportError:
    HAS_BOTO = False

@depends(HAS_BOTO)
def get_instance_meta():
    return {'instance_meta': boto.utils.get_instance_metadata()}
