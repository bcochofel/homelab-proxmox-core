FROM python:3.11-slim

# Install optional dependencies (rich)
RUN pip install --no-cache-dir rich

# Add rkhunter, lynis if you want scanning inside the container
# RUN apt-get update && apt-get install -y rkhunter lynis

WORKDIR /opt/system_report

COPY system_report.pyz /opt/system_report/system_report.pyz

ENTRYPOINT ["python3", "/opt/system_report/system_report.pyz"]
