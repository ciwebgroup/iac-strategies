# S3 Media Offload Strategy - WordPress Farm

## 🎯 Overview

Configure WordPress sites to store media (uploads) in DigitalOcean Spaces (S3-compatible) instead of local filesystem, enabling true stateless WordPress containers.

**Benefits:**
- ✅ Eliminate GlusterFS dependency (save $552/month)
- ✅ Unlimited storage scaling
- ✅ Built-in CDN via DO Spaces CDN
- ✅ Better disaster recovery
- ✅ Simpler architecture
- ✅ Faster deployments (no file sync)

**Cost Impact:**
- Remove: 2 GlusterFS nodes (-$192/month compute, -$400/month block storage)
- Add: DO Spaces storage (~$40-80/month for 2-4TB)
- **Net Savings:** ~$470-550/month

---

## 🏗️ Implementation Options

### Option 1: WP Offload Media (Recommended)

**Plugin:** https://wordpress.org/plugins/amazon-s3-and-cloudfront/

**Features:**
- ✅ Automatic upload to S3 on media upload
- ✅ URL rewriting (serves from S3/CDN)
- ✅ Optional: Remove local files after upload
- ✅ Supports DO Spaces perfectly
- ✅ Free version sufficient

**Configuration:**
```php
// wp-config.php additions
define('AS3CF_SETTINGS', serialize(array(
    'provider' => 'do',
    'access-key-id' => getenv('S3_ACCESS_KEY'),
    'secret-access-key' => getenv('S3_SECRET_KEY'),
    'bucket' => getenv('S3_BUCKET_NAME'),
    'region' => getenv('S3_REGION'),
    'domain' => 'cloudfront',  // Use DO Spaces CDN
    'cloudfront' => getenv('S3_CDN_DOMAIN'),
    'enable-object-prefix' => true,
    'object-prefix' => 'wp-content/uploads/',
    'copy-to-s3' => true,
    'serve-from-s3' => true,
    'remove-local-file' => true,  // Delete after upload
)));
```

### Option 2: Media Cloud

**Plugin:** https://wordpress.org/plugins/ilab-media-tools/

**Features:**
- ✅ More advanced features
- ✅ Image optimization
- ✅ Multiple storage backends
- ✅ CDN integration
- ✅ Admin UI for management

### Option 3: WP Stateless

**Plugin:** https://wordpress.org/plugins/wp-stateless/

**Features:**
- ✅ Google Cloud Storage native
- ✅ Works with S3-compatible
- ✅ Automatic synchronization
- ✅ Mode: Stateless (all in cloud)

---

## 📝 WordPress Site Template with S3

### Updated wordpress-site-template-s3.yml

```yaml
version: '3.8'

services:
  php-fpm:
    image: registry.yourdomain.com/wordpress-fpm:8.2-s3
    environment:
      # S3 Configuration for Media Offload
      S3_UPLOADS_BUCKET: ${S3_UPLOADS_BUCKET:-wp-farm-media}
      S3_UPLOADS_KEY: ${DO_SPACES_ACCESS_KEY}
      S3_UPLOADS_SECRET: ${DO_SPACES_SECRET_KEY}
      S3_UPLOADS_REGION: ${DO_SPACES_REGION:-nyc3}
      S3_UPLOADS_ENDPOINT: ${DO_SPACES_ENDPOINT}
      S3_UPLOADS_CDN: ${S3_CDN_DOMAIN}  # e.g., cdn.yourdomain.com
      
      # S3 Offload Plugin Auto-Configuration
      AS3CF_PROVIDER: do
      AS3CF_BUCKET: wp-site-{SITE_ID}
      AS3CF_REGION: ${DO_SPACES_REGION}
      AS3CF_COPY_TO_S3: true
      AS3CF_SERVE_FROM_S3: true
      AS3CF_REMOVE_LOCAL_FILE: true
      
      # WordPress Config
      WORDPRESS_DB_HOST: proxysql:6033
      WORDPRESS_DB_NAME: wp_site_{SITE_ID}
      # ... other WordPress config
    
    volumes:
      # NO uploads volume needed! Everything in S3
      - wp-{SITE_ID}-plugins:/var/www/html/wp-content/plugins
      - wp-{SITE_ID}-themes:/var/www/html/wp-content/themes
      # Note: uploads directory not mounted
```

---

## 🚀 Migration Strategy

### Phase 1: Setup DO Spaces

```bash
# 1. Create Spaces bucket
doctl spaces bucket create wp-farm-media --region nyc3

# 2. Enable CDN
doctl spaces bucket cdn enable wp-farm-media

# 3. Configure CORS
cat > cors.json <<EOF
{
  "CORSRules": [{
    "AllowedOrigins": ["https://*.yourdomain.com"],
    "AllowedMethods": ["GET", "PUT", "POST", "DELETE"],
    "AllowedHeaders": ["*"],
    "ExposeHeaders": ["ETag"],
    "MaxAgeSeconds": 3000
  }]
}
EOF

aws s3api put-bucket-cors \
  --bucket wp-farm-media \
  --cors-configuration file://cors.json \
  --endpoint-url=https://nyc3.digitaloceanspaces.com

# 4. Set bucket policy (public read for media)
cat > policy.json <<EOF
{
  "Version": "2012-10-17",
  "Statement": [{
    "Sid": "PublicReadGetObject",
    "Effect": "Allow",
    "Principal": "*",
    "Action": ["s3:GetObject"],
    "Resource": ["arn:aws:s3:::wp-farm-media/*"]
  }]
}
EOF

aws s3api put-bucket-policy \
  --bucket wp-farm-media \
  --policy file://policy.json \
  --endpoint-url=https://nyc3.digitaloceanspaces.com
```

### Phase 2: Install Plugin on All Sites

```bash
# Bulk install WP Offload Media on all sites
for site_id in {001..500}; do
  docker exec wp-cli-farm wp plugin install \
    amazon-s3-and-cloudfront \
    --activate \
    --url="wp-site-${site_id}.yourdomain.com"
done

# Configure plugin via WP-CLI
for site_id in {001..500}; do
  docker exec wp-cli-farm wp option update \
    tantan_wordpress_s3 \
    '{"provider":"do","bucket":"wp-site-'$site_id'","region":"nyc3",...}' \
    --url="wp-site-${site_id}.yourdomain.com" \
    --format=json
done
```

### Phase 3: Migrate Existing Media

```bash
# Use WP-CLI to copy existing uploads to S3
for site_id in {001..500}; do
  echo "Migrating site $site_id..."
  docker exec wp-cli-farm wp s3-uploads migrate \
    --url="wp-site-${site_id}.yourdomain.com"
done

# Or use AWS CLI for bulk transfer
for site_dir in /mnt/glusterfs/wp-site-*/uploads; do
  site_id=$(basename $(dirname $site_dir) | sed 's/wp-site-//')
  aws s3 sync $site_dir s3://wp-farm-media/wp-site-${site_id}/uploads/ \
    --endpoint-url=https://nyc3.digitaloceanspaces.com
done
```

### Phase 4: Verify and Decommission GlusterFS

```bash
# 1. Verify all media serving from S3
curl -I https://site-001.yourdomain.com/wp-content/uploads/2026/01/test.jpg
# Should show: x-amz-* headers or DO Spaces headers

# 2. Test uploads work
# Upload image via WordPress admin on several sites

# 3. Monitor for 1 week
# Ensure no issues with media loading

# 4. Decommission GlusterFS nodes
docker node update --availability drain wp-storage-01
docker node update --availability drain wp-storage-02

# 5. Delete nodes
doctl compute droplet delete wp-storage-01 wp-storage-02

# 6. Update cost tracking
# Savings: $552/month!
```

---

## 📊 S3 Storage Cost Calculation

### Storage Pricing

```
DO Spaces Pricing:
├── Storage: $0.02/GB/month ($20/TB)
├── Bandwidth: $0.01/GB outbound
├── First 250GB storage: Included in $5 base
└── CDN: Included (no extra cost)

Estimate for 500 Sites:
├── Average site media: 500MB
├── Total: 500 × 0.5GB = 250GB
├── Storage cost: $5/month (base price)
├── Bandwidth: ~1TB/month = $10
└── Total: $15-20/month

Growth to 2TB (4GB/site average):
├── Storage: $5 + ($20 × 1.75TB) = $40/month
├── Bandwidth: ~2TB/month = $20/month
└── Total: $60/month

Conservative estimate: $40-80/month for S3
```

### vs GlusterFS Cost

```
GlusterFS (Current):
├── 2 nodes × $96 = $192/month
├── 4TB block storage = $400/month
└── Total: $592/month

S3 Offload:
├── DO Spaces 2TB = $40/month
├── Bandwidth 2TB = $20/month
└── Total: $60/month

SAVINGS: $532/month!
```

---

## 🔧 Environment Variables (Add to env.example)

```bash
# =============================================================================
# S3 MEDIA OFFLOAD CONFIGURATION
# =============================================================================

# S3 Media Storage (DigitalOcean Spaces)
S3_MEDIA_ENABLED=true
S3_UPLOADS_BUCKET=wp-farm-media
S3_UPLOADS_PREFIX=wp-content/uploads
S3_CDN_DOMAIN=cdn.yourdomain.com  # DO Spaces CDN endpoint

# Per-Site S3 Configuration (if using separate buckets)
S3_PER_SITE_BUCKET=true  # Each site gets wp-site-XXX bucket
S3_BUCKET_PREFIX=wp-site-

# S3 Plugin Configuration
S3_PLUGIN=amazon-s3-and-cloudfront  # or ilab-media-tools, wp-stateless
S3_AUTO_CONFIGURE=true
S3_REMOVE_LOCAL_FILES=true  # Delete local after upload (stateless)
S3_SERVE_FROM_S3=true

# CDN Configuration
S3_CDN_ENABLED=true
S3_CDN_CNAME=cdn.yourdomain.com
```

---

## 📋 Migration Checklist

### Pre-Migration
- [ ] Create DO Spaces bucket(s)
- [ ] Configure CORS policy
- [ ] Enable CDN on Spaces
- [ ] Configure DNS (cdn.yourdomain.com)
- [ ] Test S3 uploads/downloads
- [ ] Document current storage size

### Migration
- [ ] Install WP Offload Media plugin on all sites
- [ ] Configure plugin (WP-CLI or API)
- [ ] Migrate existing uploads to S3
- [ ] Verify media loads from S3
- [ ] Test new uploads go to S3
- [ ] Monitor for 1 week

### Post-Migration
- [ ] Verify no local uploads being created
- [ ] Check S3 bandwidth costs
- [ ] Verify CDN serving media
- [ ] Decommission GlusterFS nodes
- [ ] Update documentation
- [ ] Train team on S3 management

---

## 🎯 Recommendation

### When to Migrate to S3

✅ **Migrate Now If:**
- GlusterFS causing performance issues
- Need unlimited storage scaling
- Want to reduce infrastructure costs
- Comfortable with S3 management
- Have time for migration (2-3 weeks)

⏸️ **Wait If:**
- GlusterFS working well
- Team unfamiliar with S3
- Budget for migration project not available
- Want to validate current architecture first

### Recommended Timeline

**Month 1-2:** Deploy with GlusterFS (current plan)  
**Month 3-4:** Evaluate S3 migration  
**Month 5:** Execute migration if beneficial  
**Result:** $470-550/month savings, simpler architecture

---

## 💡 Best Practices

### Do's ✅
- Use separate buckets per site (better isolation)
- Enable versioning (accidental delete protection)
- Set lifecycle policies (old versions cleanup)
- Use CDN (DO Spaces CDN included)
- Monitor bandwidth costs
- Keep backups separate from production media

### Don'ts ❌
- Don't use single bucket for all sites (harder to manage)
- Don't skip CORS configuration (breaks admin uploads)
- Don't forget to test thoroughly before decommissioning GlusterFS
- Don't expose S3 credentials in WordPress (use environment variables)

---

**Status:** Optional Enhancement  
**Savings:** $470-550/month  
**Complexity:** Medium (requires migration)  
**Recommended:** Phase 2 optimization (Month 3-4)

